module ApplicationHelper
  def pluralize_without_count(count, noun, plural_noun = nil)
    count == 1 ? "#{noun}" : "#{plural_noun || noun.pluralize}"
  end
end
