# frozen_string_literal: true

module HumanizeHelper
  def humanized_enum(value)
    value.tr("_", " ").capitalize.sub("Ci ", "CI ").strip
  end
end
