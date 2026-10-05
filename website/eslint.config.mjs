import js from "@eslint/js";
import stylistic from "@stylistic/eslint-plugin";
import { defineConfig, globalIgnores } from "eslint/config";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import { registerHooks } from "node:module";

const TYPESCRIPT_6_CONSUMER = /\/node_modules\/(@typescript-eslint\/[^/]+|typescript-eslint|ts-api-utils)\//;

registerHooks({
    resolve: (specifier, context, nextResolve) => nextResolve(
        specifier === "typescript" && TYPESCRIPT_6_CONSUMER.test(context.parentURL ?? "") ? "typescript-6" : specifier,
        context
    )
});

const { default: tseslint } = await import("typescript-eslint");

const INTELLIJ_LAID_OUT_NODES = [
    "JSXElement",
    "JSXElement > *",
    "JSXAttribute",
    "JSXIdentifier",
    "JSXNamespacedName",
    "JSXMemberExpression",
    "JSXSpreadAttribute",
    "JSXExpressionContainer",
    "JSXOpeningElement",
    "JSXClosingElement",
    "JSXFragment",
    "JSXOpeningFragment",
    "JSXClosingFragment",
    "JSXText",
    "JSXEmptyExpression",
    "JSXSpreadChild",
    ":function > ObjectPattern",
    ":function > ObjectPattern TSPropertySignature",
    "ConditionalExpression",
    "ArrowFunctionExpression > :not(BlockStatement).body",
    "TSUnionType",
    "TSUnionType TSPropertySignature"
];

const indent = (continuation) => ["error", 4, {
    SwitchCase: 1,
    CallExpression: { arguments: continuation },
    FunctionDeclaration: { parameters: continuation },
    FunctionExpression: { parameters: continuation },
    MemberExpression: continuation,
    ignoredNodes: INTELLIJ_LAID_OUT_NODES
}];

export default defineConfig([
    globalIgnores([
        "**/node_modules/",
        "**/dist/",
        "**/.vinext/",
        "**/.wrangler/",
        "**/.next/",
        "**/.scratch/",
        "**/worker-configuration.d.ts",
        ".claude/",
        "next-env.d.ts",
        "lib/catalog/cave-vocab.ts",
        "lib/catalog/world.ts",
        "public/wasm/"
    ]),
    {
        files: ["**/*.{js,mjs,cjs,ts,mts,cts,tsx}"],
        extends: [js.configs.recommended, tseslint.configs.recommended],
        plugins: { "@stylistic": stylistic },
        languageOptions: {
            globals: { ...globals.browser, ...globals.node, ...globals.serviceworker }
        },
        linterOptions: {
            reportUnusedDisableDirectives: "error"
        },
        rules: {
            "no-empty": ["error", { allowEmptyCatch: true }],
            "@typescript-eslint/no-unused-vars": [
                "error",
                { argsIgnorePattern: "^_", varsIgnorePattern: "^_", ignoreRestSiblings: true }
            ],
            "@stylistic/array-bracket-spacing": ["error", "never"],
            "@stylistic/arrow-spacing": "error",
            "@stylistic/block-spacing": "error",
            "@stylistic/brace-style": ["error", "1tbs"],
            "@stylistic/comma-spacing": "error",
            "@stylistic/comma-style": "error",
            "@stylistic/computed-property-spacing": ["error", "never"],
            "@stylistic/dot-location": ["error", "property"],
            "@stylistic/function-call-spacing": ["error", "never"],
            "@stylistic/generator-star-spacing": ["error", { before: false, after: true }],
            "@stylistic/indent": indent(1),
            "@stylistic/jsx-quotes": ["error", "prefer-double"],
            "@stylistic/key-spacing": "error",
            "@stylistic/keyword-spacing": "error",
            "@stylistic/linebreak-style": ["error", "unix"],
            "@stylistic/max-len": ["error", {
                code: 120,
                tabWidth: 4,
                ignoreUrls: true,
                ignoreStrings: true,
                ignoreTemplateLiterals: true,
                ignoreRegExpLiterals: true
            }],
            "@stylistic/member-delimiter-style": "error",
            "@stylistic/no-mixed-spaces-and-tabs": "error",
            "@stylistic/no-multi-spaces": ["error", { ignoreEOLComments: true }],
            "@stylistic/no-multiple-empty-lines": ["error", { max: 2, maxBOF: 0, maxEOF: 1 }],
            "@stylistic/no-tabs": "error",
            "@stylistic/no-trailing-spaces": "error",
            "@stylistic/object-curly-spacing": ["error", "always"],
            "@stylistic/padding-line-between-statements": [
                "error",
                { blankLine: "always", prev: "import", next: "*" },
                { blankLine: "any", prev: "import", next: "import" }
            ],
            "@stylistic/quotes": ["error", "double", { avoidEscape: true }],
            "@stylistic/rest-spread-spacing": ["error", "never"],
            "@stylistic/semi": ["error", "always"],
            "@stylistic/semi-spacing": "error",
            "@stylistic/space-before-blocks": "error",
            "@stylistic/space-before-function-paren": [
                "error",
                { anonymous: "always", named: "never", asyncArrow: "always" }
            ],
            "@stylistic/space-in-parens": ["error", "never"],
            "@stylistic/space-infix-ops": "error",
            "@stylistic/space-unary-ops": "error",
            "@stylistic/spaced-comment": ["error", "always", { markers: ["/"], block: { exceptions: ["*"] } }],
            "@stylistic/switch-colon-spacing": "error",
            "@stylistic/template-curly-spacing": ["error", "never"],
            "@stylistic/type-annotation-spacing": "error",
            "@stylistic/yield-star-spacing": ["error", "after"],
            "sort-imports": ["error", { ignoreCase: true, ignoreDeclarationSort: true }]
        }
    },
    {
        files: ["**/*.{ts,mts,cts,tsx}"],
        rules: {
            "@stylistic/comma-dangle": ["error", "never"]
        }
    },
    {
        name: "tsx has no .editorconfig section, so it takes the [*] continuation indent of 8",
        files: ["**/*.tsx"],
        rules: {
            "@stylistic/indent": indent(2)
        }
    },
    {
        files: ["**/*.{ts,tsx}"],
        ignores: ["tests/**", "preview-worker/**"],
        extends: [reactHooks.configs.flat.recommended]
    }
]);
