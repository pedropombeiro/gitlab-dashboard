import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bootstrap-tooltip"
export default class extends Controller {
  connect() {
    setTimeout(() => { // Need to wait for 500 ms since relative_timestamp sets data-bs-toggle class a bit too late
      var tooltipTriggerList = this.element.querySelectorAll('[data-bs-toggle="tooltip"]')
      tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl))
    }, 500);
  }
}
