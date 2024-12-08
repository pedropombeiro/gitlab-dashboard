import { Controller } from "@hotwired/stimulus";

/**
 * Add notification badge (pill) to favicon in browser tab
 * @url stackoverflow.com/questions/65719387/
 */

// Connects to data-controller="unread-badge"
export default class extends Controller {
  static values = {
    count: Number,
  };

  connect() {
    if (navigator.setAppBadge) {
      console.log("Setting app badge to", this.countValue);
      navigator.setAppBadge(this.countValue);
    } else {
      console.log("App badge not supported");
    }
  }

  countValueChanged(value, _previousValue) {
    if (navigator.setAppBadge) {
      console.log("Setting app badge to " + value);
      navigator.setAppBadge(value);
    }
  }
}
