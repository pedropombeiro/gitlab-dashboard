# frozen_string_literal: true

class PwaController < ApplicationController
  include UsernameValidationConcern

  def manifest
    @author = validate_username(params.permit(:author)[:author])
    render template: "pwa/manifest", layout: false
  end
end
