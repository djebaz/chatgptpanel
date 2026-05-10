export default [
  {
    ignores: [
      "node_modules/**",
      "coverage/**",
      "dist/**",
      "build/**",
      "src/vendor/**",
      "src/assets/**",
    ],
  },

  {
    linterOptions: {
      reportUnusedDisableDirectives: "warn",
    },
  },

  {
    files: ["src/**/*.js", "tests/**/*.js", "test/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "script",
    },
    rules: {
      "no-const-assign": "error",
      "no-dupe-keys": "error",
      "no-func-assign": "error",
      "no-import-assign": "error",
      "no-unreachable": "error",
      "no-unsafe-finally": "error",
      "valid-typeof": "error",

      "no-unused-vars": "off",
      "no-empty": "off",
      "no-undef": "off",
      "no-redeclare": "off",
      "no-useless-escape": "off",
      "no-control-regex": "off",
      "no-empty-pattern": "off",
    },
  },

  {
    files: [
      "src/pages/pipeline/concurrency.js",
      "src/pages/pipeline/download-chunks.js",
    ],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
    },
  },
];
