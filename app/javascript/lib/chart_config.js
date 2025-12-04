/**
 * Chart.js configuration utilities
 */

/**
 * Get theme colors from CSS variables
 * Checks the element with data-bs-theme attribute for proper theme context
 * @returns {Object} Theme color configuration
 */
export function getThemeColors() {
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
 * @param {Array} data - Array of data points with y values
 * @returns {Array} Sorted array
 */
export function sortByY(data) {
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
 * @param {Object} context - Chart.js context
 * @returns {boolean}
 */
export function shouldDisplayDataLabel(context) {
  if (context === undefined || context.dataset.stack !== "merged-count") {
    return false;
  }

  const dataPoints = context.dataset.data;
  if (dataPoints.length < 3) {
    return false;
  }

  const value = dataPoints[context.dataIndex].y;
  const sortedDataPoints = sortByY(dataPoints);

  return sortedDataPoints !== undefined && value >= sortedDataPoints[2].y;
}

/**
 * Create default chart options with theme support
 * @param {Object} customOptions - Custom options to merge
 * @returns {Object} Chart.js options object
 */
export function createChartOptions(customOptions = {}) {
  const colors = getThemeColors();

  const defaultOptions = {
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

  return mergeDeep(defaultOptions, customOptions);
}

/**
 * Deep merge two objects
 * @param {Object} target - Target object
 * @param {Object} source - Source object
 * @returns {Object} Merged object
 */
function mergeDeep(target, source) {
  const output = { ...target };

  if (isObject(target) && isObject(source)) {
    Object.keys(source).forEach((key) => {
      if (isObject(source[key])) {
        if (!(key in target)) {
          Object.assign(output, { [key]: source[key] });
        } else {
          output[key] = mergeDeep(target[key], source[key]);
        }
      } else {
        Object.assign(output, { [key]: source[key] });
      }
    });
  }

  return output;
}

/**
 * Check if value is an object
 * @param {*} item - Value to check
 * @returns {boolean}
 */
function isObject(item) {
  return item && typeof item === "object" && !Array.isArray(item);
}
