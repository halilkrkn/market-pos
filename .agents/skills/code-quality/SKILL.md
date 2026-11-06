---
name: code-quality
description: Enforces Clean Architecture layer boundaries, SOLID principles, pure Dart domain isolation, immutability, and anti-overengineering standards for the Market Management System (MMS) codebase. Use this skill whenever authoring, reviewing, or refactoring Dart/Flutter code or domain models.
---

# Code Quality & Clean Architecture Skill

This skill enforces strict software engineering discipline, Clean Architecture boundaries, and Clean Code standards for the **Market Management System (MMS)** project.

---

## 1. Clean Architecture Layer Discipline

Every feature in `lib/features/<feature>/` must strictly adhere to the 3-layer rule:

$$\text{presentation} \longrightarrow \text{domain} \longleftarrow \text{data}$$

### 1.1. Domain Layer (`lib/features/<feature>/domain/`)
- **Pure Dart Only:** Must NEVER import Flutter framework (`package:flutter/...`), Drift database (`package:drift/...`), HTTP clients, or external platform packages.
- **Components:** Entities, Value Objects, Use Cases, Repository Interfaces.
- **Immutability:** All domain entities must be immutable (`@immutable` or final fields with copy methods).
- **Business Rule Integrity:** Must validate business rules directly within entity/use-case boundaries (e.g. `Money` amount must be an integer; stock conversion ratios must be integer numerator/denominator).

### 1.2. Data Layer (`lib/features/<feature>/data/`)
- **Repository Implementations:** Implements repository interfaces defined in the domain layer.
- **Data Sources:** Manages local Drift SQLite DAOs, local Windows Service API HTTP calls, and DTO mappings.
- **DTO Mapping:** Transforms raw database/API models into pure domain entities and vice-versa. Never leak database schema or API DTOs into the presentation layer.

### 1.3. Presentation Layer (`lib/features/<feature>/presentation/`)
- **Riverpod State Management:** Consumes domain use cases or repository providers.
- **UI Independence:** Widgets only observe UI state and emit user intents (events). Never perform raw database queries or direct business calculations in UI widgets.

---

## 2. SOLID Principles in Practice

- **Single Responsibility (SRP):** Each class must have exactly one reason to change. Separate cart calculation from cart persistence; separate receipt printing from sale completion.
- **Open/Closed (OCP):** Extend behavior through interfaces and strategy patterns (e.g., payment method handlers: CashHandler, CardHandler).
- **Liskov Substitution (LSP):** Derived classes or mock implementations must be fully substitutable for domain repository interfaces.
- **Interface Segregation (ISP):** Prefer small, cohesive interfaces rather than giant fat repositories.
- **Dependency Inversion (DIP):** High-level domain logic must depend on abstractions (interfaces), not low-level data drivers.

---

## 3. Financial & Precision Verification Checklist

Before accepting any code:
1. [ ] Are monetary amounts stored as integer cents (`BIGINT` / `int`)? (Zero floating-point `double` for currency!).
2. [ ] Are units of measure handled via rational integer fraction (`conversion_factor_numerator` / `denominator`)?
3. [ ] Are database operations wrapped in atomic local transactions?
4. [ ] Does the code avoid unnecessary abstractions, artificial microservices, or premature factories (YAGNI & KISS)?

