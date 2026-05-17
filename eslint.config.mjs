export default [
  {
    ignores: [
      "node_modules/**",
      "coverage/**",
      "dist/**",
      "build/**",
      "src/vendor/**",
      "src/icons/**",
    ],
  },

  {
    linterOptions: {
      reportUnusedDisableDirectives: "warn",
    },
  },

  {
    files: ["src/**/*.js", "tests/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        chrome: "readonly",
        window: "readonly",
        document: "readonly",
        console: "readonly",
        navigator: "readonly",
        URL: "readonly",
        Element: "readonly",
        MutationObserver: "readonly",
        queueMicrotask: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        process: "readonly"
      }
    },
    rules: {
      "no-const-assign": "error",
      "no-dupe-keys": "error",
      "no-func-assign": "error",
      "no-import-assign": "error",
      "no-unreachable": "error",
      "no-unsafe-finally": "error",
      "valid-typeof": "error",

      "no-unused-vars": "warn",
      "no-undef": "error",
      "no-empty": "warn",
      "no-redeclare": "error",
      "no-useless-escape": "warn",
      "no-control-regex": "off",
      "no-empty-pattern": "warn",
    },
  },
];
