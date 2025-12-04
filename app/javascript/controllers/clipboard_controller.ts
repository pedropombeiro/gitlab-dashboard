import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="clipboard"
export default class ClipboardController extends Controller {
  static targets = ["source"];

  declare readonly sourceTarget: HTMLElement;

  copy(event: Event): void {
    event.preventDefault();

    navigator.clipboard.writeText(this.sourceTarget.innerText);
  }
}
