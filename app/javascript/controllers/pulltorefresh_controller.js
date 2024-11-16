import { Controller } from "@hotwired/stimulus"
import PullToRefresh from 'pulltorefreshjs/dist';

// Connects to data-controller="pulltorefresh"
export default class extends Controller {
  connect() {
    PullToRefresh.init({
      mainElement: this.element,
      onRefresh() {
        this.element.reload();
      }
    });
  }
}
