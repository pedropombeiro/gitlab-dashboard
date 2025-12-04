import js from "@eslint/js";
import prettier from "eslint-plugin-prettier/recommended";

export default [
  js.configs.recommended,
  prettier,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        window: "readonly",
        document: "readonly",
        console: "readonly",
        Chart: "readonly",
        ChartDataLabels: "readonly",
        Notification: "readonly",
        navigator: "readonly",
        localStorage: "readonly",
        fetch: "readonly",
        alert: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        getComputedStyle: "readonly",
        AbortController: "readonly",
        Date: "readonly",
        URI: "readonly",
        TextDecoder: "readonly",
        location: "readonly",
        bootstrap: "readonly",
        Image: "readonly",
      },
    },
    rules: {
      "prettier/prettier": "warn",
      "no-console": ["warn", { allow: ["warn", "error"] }],
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
  {
    ignores: ["app/assets/builds/**", "node_modules/**", "vendor/**"],
  },
];
