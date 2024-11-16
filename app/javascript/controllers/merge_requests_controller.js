import { Controller } from "@hotwired/stimulus"
import PullToRefresh from 'pulltorefreshjs/dist';

// Connects to data-controller="merge-requests"
export default class extends Controller {
  connect() {
    PullToRefresh.init({
      mainElement: 'merge_requests',
      onRefresh() {
        merge_requests.reload();
      }
    });
  }
}
