import { Controller } from "@hotwired/stimulus";

// Keep list preferences outside the refreshed Turbo Frame.
export default class MrListController extends Controller<HTMLElement> {
  static targets = ["row", "filter", "search", "empty", "result"];

  declare readonly rowTargets: HTMLTableRowElement[];
  declare readonly filterTargets: HTMLButtonElement[];
  declare readonly searchTarget: HTMLInputElement;
  declare readonly hasSearchTarget: boolean;
  declare readonly emptyTarget: HTMLElement;
  declare readonly hasEmptyTarget: boolean;
  declare readonly resultTarget: HTMLElement;
  declare readonly hasResultTarget: boolean;

  private selectedFilter = "all";
  private query = "";
  private expandedDetails = new Set<string>();
  private pendingFocus: string | null = null;
  private updateQueued = false;

  connect(): void {
    this.element.addEventListener("turbo:before-frame-render", this.captureFocus);
    document.addEventListener("turbo:before-stream-render", this.beforeStreamRender);
    this.scheduleUpdate();
  }

  disconnect(): void {
    this.element.removeEventListener("turbo:before-frame-render", this.captureFocus);
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender);
  }

  rowTargetConnected(): void {
    this.scheduleUpdate();
  }

  searchTargetConnected(): void {
    this.scheduleUpdate();
  }

  filter(event: Event): void {
    this.selectedFilter = (event.currentTarget as HTMLButtonElement).dataset.filter || "all";
    this.applyFilters();
  }

  search(): void {
    this.query = this.searchTarget.value;
    this.applyFilters();
  }

  rememberDetails(event: Event): void {
    const details = event.target as HTMLDetailsElement;
    if (details.open) {
      this.expandedDetails.add(details.id);
    } else {
      this.expandedDetails.delete(details.id);
    }
  }

  private captureFocus = (): void => {
    const active = document.activeElement;
    this.pendingFocus = active instanceof HTMLElement && this.element.contains(active) ? active.id || null : null;
  };

  private beforeStreamRender = (event: Event): void => {
    const stream = event.target as HTMLElement;
    const target = document.getElementById(stream.getAttribute("target") || "");
    if (target && this.element.contains(target)) this.captureFocus();
  };

  private scheduleUpdate(): void {
    if (this.updateQueued) return;
    this.updateQueued = true;
    window.queueMicrotask(() => {
      this.updateQueued = false;
      if (!this.element.isConnected) return;
      if (this.hasSearchTarget) this.searchTarget.value = this.query;
      this.element.querySelectorAll<HTMLDetailsElement>("details[id]").forEach((details) => {
        details.open = this.expandedDetails.has(details.id);
      });
      this.applyFilters();
      if (this.pendingFocus) {
        const target = document.getElementById(this.pendingFocus);
        if (target && !target.closest("[hidden]")) target.focus({ preventScroll: true });
        this.pendingFocus = null;
      }
    });
  }

  private applyFilters(): void {
    const query = this.query.trim().toLocaleLowerCase();
    let visible = 0;
    this.rowTargets.forEach((row) => {
      const matchesFilter = this.selectedFilter === "all" || row.dataset[this.selectedFilter] === "true";
      row.hidden = !matchesFilter || !(row.dataset.search || "").includes(query);
      if (!row.hidden) visible++;
    });
    this.filterTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.filter === this.selectedFilter));
    });
    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible > 0;
    if (this.hasResultTarget) {
      this.resultTarget.textContent = `${visible} of ${this.rowTargets.length} merge requests shown`;
    }
  }
}
