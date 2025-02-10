# frozen_string_literal: true

module ColorHelper
  # Soft, distinct colors that won't be confused with status indicators
  PALETTE = [
    {bg: "#FF6B6B", text_class: "text-white"},   # Vibrant red
    {bg: "#FF8787", text_class: "text-black"},   # Coral
    {bg: "#E599F7", text_class: "text-black"},   # Light purple
    {bg: "#F06595", text_class: "text-white"},   # Deep pink
    {bg: "#20C997", text_class: "text-white"},   # Teal
    {bg: "#51CF66", text_class: "text-white"},   # Rich green
    {bg: "#94D82D", text_class: "text-black"},   # Lime green
    {bg: "#9775FA", text_class: "text-white"},   # Rich purple
    {bg: "#845EF7", text_class: "text-white"},   # Deep indigo
    {bg: "#5C7CFA", text_class: "text-white"},   # Royal blue
    {bg: "#339AF0", text_class: "text-white"},   # Ocean blue
    {bg: "#66D9E8", text_class: "text-black"},   # Sky blue
    {bg: "#3BC9DB", text_class: "text-black"},   # Turquoise
    {bg: "#FF922B", text_class: "text-white"},   # Deep orange
    {bg: "#FCC419", text_class: "text-black"}    # Golden yellow
  ].freeze

  def branch_color(branch_name)
    return nil if branch_name.blank?

    # Use the issue number to deterministically select a color
    index = Zlib.crc32(branch_name, 0) % PALETTE.length
    PALETTE[index][:bg]
  end

  def issue_color(issue_number)
    return nil if issue_number.nil?

    # Use the issue number to deterministically select a color
    index = issue_number.to_i % PALETTE.length
    PALETTE[index]
  end
end
