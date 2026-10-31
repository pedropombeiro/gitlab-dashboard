require "open3"
require "securerandom"
require "tmpdir"

RSpec.describe "bin/with-file-env" do
  let(:script) { File.expand_path("../../bin/with-file-env", __dir__) }
  let(:secret) { "s3cr3t-#{SecureRandom.hex(8)}" }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def write_secret(name, content)
    File.join(dir, name).tap { |path| File.write(path, content) }
  end

  # Runs the script under /bin/sh with only the given variables, plus PATH.
  def run_script(env, *command)
    Open3.capture3({"PATH" => ENV.fetch("PATH"), **env}, "/bin/sh", script, *command, unsetenv_others: true)
  end

  # Exits 0 only when $NAME equals the expected value, without printing it.
  def check_value(name, expected)
    ["/bin/sh", "-c", %(test "${#{name}-unset}" = "$1"), "check", expected]
  end

  shared_examples "does not leak the secret" do
    it "keeps the value out of stdout and stderr" do
      stdout, stderr, = result

      expect(stdout).not_to include(secret)
      expect(stderr).not_to include(secret)
    end
  end

  context "when NAME_FILE points to a readable file" do
    let(:path) { write_secret("token", secret) }
    let(:result) { run_script({"GITLAB_TOKEN_FILE" => path}, *check_value("GITLAB_TOKEN", secret)) }

    it "exports the file contents as NAME" do
      expect(result.last).to be_success
    end

    it "unsets NAME_FILE" do
      _, _, status = run_script({"GITLAB_TOKEN_FILE" => path}, *check_value("GITLAB_TOKEN_FILE", "unset"))

      expect(status).to be_success
    end

    include_examples "does not leak the secret"
  end

  context "when the file ends with newlines" do
    let(:path) { write_secret("token", "#{secret}\n\n") }
    let(:result) { run_script({"GITLAB_TOKEN_FILE" => path}, *check_value("GITLAB_TOKEN", secret)) }

    it "strips the trailing newlines" do
      expect(result.last).to be_success
    end
  end

  context "when the value spans several lines" do
    let(:value) { "line one\nline two" }
    let(:path) { write_secret("multi", "#{value}\n") }

    it "keeps the inner newlines" do
      _, _, status = run_script({"MULTI_FILE" => path}, *check_value("MULTI", value))

      expect(status).to be_success
    end
  end

  context "when both NAME and NAME_FILE are set" do
    let(:path) { write_secret("token", "from-file-#{secret}") }
    let(:result) { run_script({"GITLAB_TOKEN" => secret, "GITLAB_TOKEN_FILE" => path}, "true") }

    it "fails and names the variables" do
      _, stderr, status = result

      expect(status.exitstatus).to eq(1)
      expect(stderr).to eq("with-file-env: both GITLAB_TOKEN and GITLAB_TOKEN_FILE are set; set only one\n")
    end

    include_examples "does not leak the secret"
  end

  context "when NAME_FILE points to a missing file" do
    let(:path) { File.join(dir, "missing") }
    let(:result) { run_script({"GITLAB_TOKEN_FILE" => path}, "true") }

    it "fails and names the variable and the path" do
      _, stderr, status = result

      expect(status.exitstatus).to eq(1)
      expect(stderr).to eq("with-file-env: GITLAB_TOKEN_FILE: cannot read '#{path}'\n")
    end
  end

  context "when NAME_FILE points to a directory" do
    let(:result) { run_script({"GITLAB_TOKEN_FILE" => dir}, "true") }

    it "fails and names the variable and the path" do
      _, stderr, status = result

      expect(status.exitstatus).to eq(1)
      expect(stderr).to eq("with-file-env: GITLAB_TOKEN_FILE: cannot read '#{dir}'\n")
    end
  end

  context "when NAME_FILE points to an unreadable file" do
    let(:path) { write_secret("token", secret).tap { |p| File.chmod(0o000, p) } }
    let(:result) { run_script({"GITLAB_TOKEN_FILE" => path}, "true") }

    before { skip "root can read any file" if Process.uid.zero? }

    it "fails and names the variable and the path" do
      _, stderr, status = result

      expect(status.exitstatus).to eq(1)
      expect(stderr).to eq("with-file-env: GITLAB_TOKEN_FILE: cannot read '#{path}'\n")
    end

    include_examples "does not leak the secret"
  end

  context "when NAME_FILE is empty" do
    it "ignores it" do
      _, _, status = run_script({"GITLAB_TOKEN_FILE" => ""}, *check_value("GITLAB_TOKEN", "unset"))

      expect(status).to be_success
    end
  end

  context "when only a plain variable is set" do
    let(:result) { run_script({"GITLAB_TOKEN" => secret}, *check_value("GITLAB_TOKEN", secret)) }

    it "leaves it unchanged" do
      expect(result.last).to be_success
    end

    include_examples "does not leak the secret"
  end

  it "passes arguments and the exit status through" do
    stdout, _, status = run_script({}, "/bin/sh", "-c", 'printf "%s|" "$@"; exit 3', "sh", "a b", "c")

    expect(stdout).to eq("a b|c|")
    expect(status.exitstatus).to eq(3)
  end

  it "fails without a command" do
    _, stderr, status = run_script({})

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("usage:")
  end
end
