import { Controller } from "@hotwired/stimulus";

/**
 * Add notification badge (pill) to favicon in browser tab
 * @url stackoverflow.com/questions/65719387/
 */
class Badger {
  constructor(options) {
    Object.assign(
      this,
      {
        backgroundColor: "#198754",
        color: "#fff",
        size: 0.7, // 0..1 (Scale in respect to the favicon image size)
        position: "se", // Position inside favicon "n", "e", "s", "w", "ne", "nw", "se", "sw"
        radius: 0.1, // Border radius, better used as % value + 4px base
        src: "", // Favicon source (dafaults to the <link> icon href),
        srcs: false,
        onChange() { },
      },
      options,
    );
    this.canvas = document.createElement("canvas");
    this.ctx = this.canvas.getContext("2d");

    this.src = "";
    this.img = "";
    this.srcs = this.srcs || this.faviconELs;
  }

  faviconELs = document.querySelectorAll("link[rel$=icon]");

  _drawIcon() {
    this.ctx.clearRect(0, 0, this.faviconSize, this.faviconSize);
    this.ctx.drawImage(this.img, 0, 0, this.faviconSize, this.faviconSize);
  }

  _drawShape() {
    const r = Math.floor(this.faviconSize * this.radius) + 4;
    const xa = this.offset.x;
    const ya = this.offset.y;
    const xb = this.offset.x + this.badgeSize;
    const yb = this.offset.y + this.badgeSize;
    this.ctx.beginPath();
    this.ctx.moveTo(xb - r, ya);
    this.ctx.quadraticCurveTo(xb, ya, xb, ya + r);
    this.ctx.lineTo(xb, yb - r);
    this.ctx.quadraticCurveTo(xb, yb, xb - r, yb);
    this.ctx.lineTo(xa + r, yb);
    this.ctx.quadraticCurveTo(xa, yb, xa, yb - r);
    this.ctx.lineTo(xa, ya + r);
    this.ctx.quadraticCurveTo(xa, ya, xa + r, ya);
    this.ctx.fillStyle = this.backgroundColor;
    this.ctx.fill();
    this.ctx.closePath();
  }

  _drawVal() {
    const margin = (this.badgeSize * 0.18) / 2;
    this.ctx.beginPath();
    this.ctx.textBaseline = "middle";
    this.ctx.textAlign = "center";
    this.ctx.font = `bold ${this.badgeSize * 0.82}px Arial`;
    this.ctx.fillStyle = this.color;
    this.ctx.fillText(this.value, this.badgeSize / 2 + this.offset.x, this.badgeSize / 2 + this.offset.y + margin);
    this.ctx.closePath();
  }

  _drawFavicon() {
    this.src.setAttribute("href", this.dataURL);
  }

  _draw() {
    this._drawIcon();
    if (this.value) this._drawShape();
    if (this.value) this._drawVal();
  }

  _setup(el) {
    this.img = el.img;
    this.src = el.src;

    this.faviconSize = this.img.naturalWidth;
    this.badgeSize = this.faviconSize * this.size;
    this.canvas.width = this.faviconSize;
    this.canvas.height = this.faviconSize;
    const sd = this.faviconSize - this.badgeSize;
    const sd2 = sd / 2;
    this.offset = {
      n: { x: sd2, y: 0 },
      e: { x: sd, y: sd2 },
      s: { x: sd2, y: sd },
      w: { x: 0, y: sd2 },
      nw: { x: 0, y: 0 },
      ne: { x: sd, y: 0 },
      sw: { x: 0, y: sd },
      se: { x: sd, y: sd },
    }[this.position];
  }

  // Public functions / methods:
  imgs = [];
  updateAll() {
    this._value = Math.min(99, parseInt(this._value, 10));
    var self = this;

    if (this.imgs.length) {
      this.imgs.forEach(function (img) {
        self._setup(img);
        self._draw();
        self._drawFavicon();
      });
      if (this.onChange) this.onChange.call(this);
    } else {
      // load all
      this.srcs.forEach(function (src) {
        var img = {};
        img.img = new Image();
        img.img.addEventListener("load", () => {
          self._setup(img);
          self._draw();
          self._drawFavicon();
          if (self.onChange) self.onChange.call(self);
        });
        img.src = src;
        img.img.src = src.getAttribute("href");
        self.imgs.push(img);
      });
    }
  }

  get dataURL() {
    return this.canvas.toDataURL();
  }

  get value() {
    return this._value;
  }

  set value(val) {
    this._value = val;
    this.updateAll();
  }

  set problem(val) {
    this.backgroundColor = val ? "#dc3545" : "#198754";
    this.updateAll();
  }
}

var badgerOptions = {}; // See: constructor for customization options
var badger = new Badger(badgerOptions);

// Connects to data-controller="unread-badge"
export default class extends Controller {
  static values = {
    count: Number,
    problem: Boolean,
  };

  connect() {
    badger.value = this.countValue;
    badger.problem = this.problemValue;
  }

  countValueChanged(value, _previousValue) {
    badger.value = value;
  }

  problemValueChanged(value, _previousValue) {
    badger.problem = value;
  }
}
