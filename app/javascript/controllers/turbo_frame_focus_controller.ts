import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="turbo-frame-focus"
// Manages focus after Turbo Frame updates for better keyboard/screen reader accessibility
export default class TurboFrameFocusController extends Controller {
  static targets = ["frame"];

  declare readonly hasFrameTarget: boolean;
  declare readonly frameTarget: HTMLElement;

  connect(): void {
    // Listen for turbo:frame-render event to manage focus after updates
    this.element.addEventListener("turbo:frame-render", this.handleFrameRender.bind(this));
  }

  private handleFrameRender(event: Event): void {
    // Only handle events from our frame
    if (!this.hasFrameTarget || event.target !== this.frameTarget) {
      return;
    }

    // Find first focusable element or heading in the updated frame
    const focusableElement = this.findFocusTarget();

    if (focusableElement) {
      // Store current scroll position
      const scrollY = window.scrollY;

      // Focus the element
      focusableElement.focus();

      // Restore scroll position (focus can cause unwanted scrolling)
      window.scrollTo(0, scrollY);
    }
  }

  private findFocusTarget(): HTMLElement | null {
    if (!this.hasFrameTarget) {
      return null;
    }

    // Try to find a heading (h1-h6) or caption as the first focus target
    const heading = this.frameTarget.querySelector("h1, h2, h3, h4, h5, h6, caption, .lead") as HTMLElement | null;

    if (heading) {
      // Make heading focusable if it isn't already
      if (!heading.hasAttribute("tabindex")) {
        heading.setAttribute("tabindex", "-1");
      }
      return heading;
    }

    // Fallback to first interactive element
    const focusableSelector = 'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])';
    return this.frameTarget.querySelector(focusableSelector) as HTMLElement | null;
  }
}
