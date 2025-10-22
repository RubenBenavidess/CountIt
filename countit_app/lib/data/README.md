# Purpose: 
implement data access, DTOs, and non-critical business logic, isolating UI from transport details with repositories/services.

## Use it for: 
remote clients, repository implementations, and serialization that map API payloads to app types.

## Contains: 
/remote for API/SDK clients and /dtos for request/response models, optionally concrete repositories behind interfaces.

## Avoid: 
widgets, routing, or theme; never expose raw transport types to the UI layer.