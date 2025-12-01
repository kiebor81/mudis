# Contributing to Mudis

---

## Project Goals

Mudis is a lightweight, Ruby-native, in-memory cache intended for:

- Per-process or per-thread caching
- Fast LRU eviction with optional compression
- Clear and observable behavior
- Configuration via Ruby DSL
- No external services or runtime dependencies

**Mudis is not a distributed system, nor a replacement for Redis or Memcached.**

---

### Scope

Before submitting an issue or pull request, please read the following:

| In-Scope ✅                | Out-of-Scope ❌                                           |
|---------------------------|-----------------------------------------------------------|
| In-process memory cache   | Multi-node or clustered caches                            |
| Observability features    | Built-in persistence or disk-based storage                |
| Compression + serialization | Language-agnostic protocol support                      |
| Namespacing, TTL, limits  | Background sync across nodes                 |
| Thread safety             | Network daemons or long-running cache servers             |

If you're exploring a feature outside the scope, we recommend building on top of Mudis or forking to suit your architecture.

---

### How to Contribute

1. **Fork the repo** and create your feature branch:  
   `git checkout -b my-feature`

2. **Write clear, test-covered code** using RSpec and Rubocop standards

3. **Document your changes**, especially in:
   - `README.md` for features
   - `CHANGELOG.md` for version updates

4. **Run the test suite**  
```bash
   bundle install
   bundle exec rspec
```

5. **Push your branch and open a Pull Request**

### Development Setup

```bash
git clone https://github.com/your-name/mudis.git
cd mudis
bundle install
bundle exec rspec
```

#### Running Tests with Coverage

To run the full test suite with coverage reporting:

```bash
rake coverage
```

This will:
- Execute all RSpec tests
- Generate a coverage report (92%+ expected on non-Windows platforms)
- Automatically open the HTML coverage report in your browser

The coverage report is saved to `coverage/index.html` and shows line-by-line test coverage.

**Note:** On Windows, UNIX socket tests are skipped as they're not supported on that platform.

### Code Standards

- Follow the existing naming and structure patterns
- Keep the core class lean and testable
- Avoid side effects in configuration
- All public methods must be tested

### PRs That May Be Rejected

- Features that introduce persistence, cluster sync, or background services
- HTTP/daemon layers inside the core gem (consider a separate project)
- Language-agnostic interface requests (Mudis is Ruby-first)
- PRs with no tests or documentation