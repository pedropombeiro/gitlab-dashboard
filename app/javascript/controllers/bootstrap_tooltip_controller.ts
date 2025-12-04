import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="bootstrap-tooltip"
export default class BootstrapTooltipController extends Controller {
  connect(): void {
    setTimeout(() => {
      // Need to wait for 500 ms since relative_timestamp sets data-bs-toggle class a bit too late
      const tooltipTriggerList = this.element.querySelectorAll('[data-bs-toggle="tooltip"]');
      [...tooltipTriggerList].map((tooltipTriggerEl) => new bootstrap.Tooltip(tooltipTriggerEl));

      const popoverTriggerList = this.element.querySelectorAll('[data-bs-toggle="popover"]');
      [...popoverTriggerList].map((popoverTriggerEl) => new bootstrap.Popover(popoverTriggerEl));
    }, 500);
  }
}
