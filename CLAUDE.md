# Photon Development Rules & Tooling Policy

## Primary Tooling Directive: Android Studio (`studio` MCP)
You have direct integration with Android Studio via the `studio` MCP server. For every code-related task, you MUST prioritize `studio` tools over generic terminal search or blind file edits:

1. **Pre-Task Orientation:**
    - Before editing or answering questions about active work, call `studio` to check the currently active file, open editor tabs, and cursor selection to understand what is on screen.

2. **Code Search & Navigation:**
    - Never use raw grep or regex find when searching for classes, methods, or variables.
    - Use `studio` semantic symbol search, definition lookup, and "find usages" so navigation respects the Dart AST and type hierarchy.

3. **Post-Edit Verification:**
    - Immediately after writing or modifying Dart/Flutter code or shader files, call `studio` diagnostics to read real-time IDE compile errors and linter warnings.
    - Do not consider a task complete until `studio` diagnostics confirm zero errors on touched files.

4. **Refactoring & Formatting:**
    - Prefer `studio` symbol renaming and IDE-native formatting over manual search-and-replace to prevent breaking cross-file references.