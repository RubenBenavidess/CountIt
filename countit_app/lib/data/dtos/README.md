# Purpose: 
request/response transfer models that mirror API contracts while decoupling the rest of the app from schema changes.

## Contains:
@JsonSerializable classes with @JsonKey for names/defaults and generated toJson/fromJson.

## Avoid: 
UI logic, transport concerns beyond faithful mapping, or business validation.

## Key practices:
null safety with defaults, stable field names, and versioned tests for round-trip JSON stability.

## Testing: 
round-trip JSON → DTO → JSON and sample payload fixtures per endpoint version.​