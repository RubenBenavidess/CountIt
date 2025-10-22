## Purpose:
declare pages and widgets, bind to ViewModel state, and trigger ViewModel actions without data access or side-effects.

## Contains:
page widget, internal widgets, state listeners, and navigation hooks that delegate to the app router.

## Avoid:
data fetching, DTO mapping, network error handling, or DI wiring in widgets.

## Key practices:
small, composable widgets, styles via theme tokens, and navigation through the centralized router.

## Testing:
golden tests and interaction tests that mock ViewModel outputs.

## Naming:
<feature>_page.dart for main screen and descriptive names for sub-widgets.