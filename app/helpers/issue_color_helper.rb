# frozen_string_literal: true

module IssueColorHelper
  # Soft, distinct colors that won't be confused with status indicators
  PALETTE = [
    {bg: "#FF6B6B", text_class: "text-white"},   # Vibrant red
    {bg: "#4DABF7", text_class: "text-white"},   # Strong blue
    {bg: "#9775FA", text_class: "text-white"},   # Rich purple
    {bg: "#FF922B", text_class: "text-white"},   # Deep orange
    {bg: "#51CF66", text_class: "text-black"},   # Rich green
    {bg: "#FF8ED4", text_class: "text-black"},   # Bright pink
    {bg: "#FF9F1C", text_class: "text-black"},   # Bright yellow
    {bg: "#5C7CFA", text_class: "text-white"},   # Royal blue
    {bg: "#BE4BDB", text_class: "text-white"},   # Deep purple
    {bg: "#20C997", text_class: "text-white"}    # Teal
  ].freeze

  def issue_color(issue_number)
    return nil if issue_number.nil?

    # Use the issue number to deterministically select a color
    index = issue_number.to_i % PALETTE.length
    PALETTE[index]
  end

  # Alternative method that uses Bootstrap badges instead of dots
  def issue_badge(issue_number)
    return "" if issue_number.nil?

    color = issue_color(issue_number)
    content_tag(:span, "##{issue_number}",
      class: %W[badge rounded-pill #{color[:text_class]}],
      style: "background-color: #{color[:bg]} !important;")
  end
end
