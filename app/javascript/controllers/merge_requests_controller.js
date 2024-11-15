import { Controller } from "@hotwired/stimulus"
import PullToRefresh from 'pulltorefreshjs/dist';

// Connects to data-controller="merge-requests"
export default class extends Controller {
  connect() {
    const ptr = PullToRefresh.init({
      mainElement: 'merge_requests',
      onRefresh() {
        window.location.reload();
      }
    });
  }
}
