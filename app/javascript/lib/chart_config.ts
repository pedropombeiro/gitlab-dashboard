/**
 * Chart.js configuration utilities
 */

import type { ChartOptions } from "chart.js";
import type { Context } from "chartjs-plugin-datalabels";

/**
 * Theme color configuration
 */
export interface ThemeColors {
  text: string;
  grid: string;
  bg: string;
  border: string;
}

/**
 * Data point with y-value
 */
interface DataPoint {
  y: number;
  [key: string]: unknown;
}

/**
 * Get theme colors from CSS variables
 * Checks the element with data-bs-theme attribute for proper theme context
 */
export function getThemeColors(): ThemeColors {
  // Find the element with the theme attribute (usually on body or a container)
  const themedElement = document.querySelector("[data-bs-theme]") || document.documentElement;
  const styles = getComputedStyle(themedElement);

  return {
    text: styles.getPropertyValue("--chart-text-color").trim(),
    grid: styles.getPropertyValue("--chart-grid-color").trim(),
    bg: styles.getPropertyValue("--chart-bg-color").trim(),
    border: styles.getPropertyValue("--chart-border-color").trim(),
  };
}

/**
 * Sort data points by y-value in descending order
 */
export function sortByY(data: DataPoint[]): DataPoint[] {
  if (!Array.isArray(data)) {
    throw new Error("Input must be an array.");
  }

  if (data.length === 0) {
    return [];
  }

  return [...data].sort((a, b) => b.y - a.y);
}

/**
 * Determine if a data label should be displayed
 * Only show labels for the top 3 values in the merged-count stack
 */
export function shouldDisplayDataLabel(context: Context): boolean {
  if (context === undefined || context.dataset.stack !== "merged-count") {
    return false;
  }

  const dataPoints = context.dataset.data as unknown as DataPoint[];
  if (dataPoints.length < 3) {
    return false;
  }

  const value = dataPoints[context.dataIndex]?.y;
  if (value === undefined) {
    return false;
  }

  const sortedDataPoints = sortByY(dataPoints);
  const thirdHighest = sortedDataPoints[2];

  return thirdHighest !== undefined && value >= thirdHighest.y;
}

/**
 * Create default chart options with theme support
 */
export function createChartOptions(customOptions: Partial<ChartOptions> = {}): ChartOptions {
  const colors = getThemeColors();

  const defaultOptions: ChartOptions = {
    responsive: true,
    maintainAspectRatio: true,
    scales: {
      x: {
        ticks: { color: colors.text },
        grid: { color: colors.grid },
      },
      y: {
        ticks: { color: colors.text },
        grid: { color: colors.grid },
      },
    },
    plugins: {
      legend: {
        labels: { color: colors.text },
      },
    },
  };

  return mergeDeep(defaultOptions, customOptions) as ChartOptions;
}

/**
 * Deep merge two objects
 */
function mergeDeep<T extends Record<string, unknown>>(target: T, source: Partial<T>): T {
  const output = { ...target };

  if (isObject(target) && isObject(source)) {
    Object.keys(source).forEach((key) => {
      const sourceValue = source[key as keyof T];
      const targetValue = target[key as keyof T];

      if (isObject(sourceValue)) {
        if (!(key in target)) {
          Object.assign(output, { [key]: sourceValue });
        } else if (isObject(targetValue)) {
          output[key as keyof T] = mergeDeep(
            targetValue as Record<string, unknown>,
            sourceValue as Record<string, unknown>
          ) as T[keyof T];
        }
      } else {
        Object.assign(output, { [key]: sourceValue });
      }
    });
  }

  return output;
}

/**
 * Check if value is an object
 */
function isObject(item: unknown): item is Record<string, unknown> {
  return item !== null && typeof item === "object" && !Array.isArray(item);
}
