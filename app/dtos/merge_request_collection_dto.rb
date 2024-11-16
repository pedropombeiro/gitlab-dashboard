# frozen_string_literal: true

class MergeRequestCollectionDto
  attr_reader :items

  def initialize(items)
    @items = items
  end
end
