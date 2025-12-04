import type { Chart } from "chart.js";
import type { Tooltip, Popover, Dropdown } from "bootstrap";

declare global {
  interface Window {
    Chart: typeof Chart;
    ChartDataLabels: unknown;
    bootstrap: {
      Tooltip: typeof Tooltip;
      Popover: typeof Popover;
      Dropdown: typeof Dropdown;
    };
  }

  // Make bootstrap global
  const bootstrap: {
    Tooltip: typeof Tooltip;
    Popover: typeof Popover;
    Dropdown: typeof Dropdown;
  };
}

export {};
