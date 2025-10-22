# Purpose: 
encapsulate HTTP or SDK calls in API classes with typed methods per use case and consistent error propagation.

## Contains: 
e.g., wallet_api.dart with methods like fetchHistory and transfer, timeouts/retries, and response conversion to DTOs.

## Supabase: 
initialize the client via DI and consume it here following the official Flutter quickstart.

## Avoid: 
UI state or widget dependencies; never leak transport-specific models beyond DTO boundaries.

## Key practices: 
inject clients, avoid global singletons, and surface typed exceptions for mapping in the App/errors layer.

## Testing: 
integration tests with test instances or mocked SDKs and verification of error codes/paths.
​