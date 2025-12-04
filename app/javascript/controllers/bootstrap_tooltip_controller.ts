import { Controller } from "@hotwired/stimulus";
import type { Tooltip, Popover } from "bootstrap";

// Connects to data-controller="bootstrap-tooltip"
export default class BootstrapTooltipController extends Controller {
  private tooltips: Tooltip[] = [];
  private popovers: Popover[] = [];
  private timeoutId: ReturnType<typeof setTimeout> | null = null;

  connect(): void {
    this.timeoutId = setTimeout(() => {
      // Need to wait for 500 ms since relative_timestamp sets data-bs-toggle class a bit too late
      this.initializeTooltips();
      this.initializePopovers();
    }, 500);
  }

  disconnect(): void {
    // Clean up timeout if component disconnects before it fires
    if (this.timeoutId !== null) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }

    // Dispose all tooltips to prevent memory leaks and stuck tooltips
    this.tooltips.forEach((tooltip) => tooltip.dispose());
    this.tooltips = [];

    // Dispose all popovers
    this.popovers.forEach((popover) => popover.dispose());
    this.popovers = [];
  }

  private initializeTooltips(): void {
    const tooltipTriggerList = this.element.querySelectorAll('[data-bs-toggle="tooltip"]');

    this.tooltips = [...tooltipTriggerList].map((tooltipTriggerEl) => {
      // Check if tooltip already exists and dispose it first
      bootstrap.Tooltip.getInstance(tooltipTriggerEl)?.dispose();

      return new bootstrap.Tooltip(tooltipTriggerEl);
    });
  }

  private initializePopovers(): void {
    const popoverTriggerList = this.element.querySelectorAll('[data-bs-toggle="popover"]');

    this.popovers = [...popoverTriggerList].map((popoverTriggerEl) => {
      // Check if popover already exists and dispose it first
      bootstrap.Popover.getInstance(popoverTriggerEl)?.dispose();

      return new bootstrap.Popover(popoverTriggerEl, {
        html: true,
      });
    });
  }
}
