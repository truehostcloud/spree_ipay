# GitHub Copilot Instructions

This document provides coding guidelines and best practices for this project to help GitHub Copilot generate better code suggestions.

## Code Quality Guidelines

## Copilot Response Guidelines

- **Proceed directly without asking for confirmation unless the action is illegal or dangerous**: If you have enough information to resolve a problem or error, execute the fix immediately. Do not ask for permission or confirmation unless the action could be unsafe, illegal, or destructive. For example, do not ask "Would you like me to check and fix..."—just check and fix it.
- **Use system-level instructions if available**: If the API or platform allows, set a system role message or instruction (e.g., "You are an assistant that executes tasks immediately unless they violate safety guidelines.") to reinforce this behavior at the system level.
- **Explain the cause and solution clearly**: When you identify an issue, briefly explain why it occurs and what you are doing to resolve it, then proceed with the fix.


### Comments
- **Do not use inline code comments**: Code must be self-documenting through clear variable names, function names, and structure. Inline comments (comments on the same line as code or comments explaining what the code does) are not allowed
- **Use docstrings for functions and classes**: Document their purpose, parameters, and return values
- **Docstring line length**: All docstrings must wrap at 88 characters or less per line. Break lines naturally at word boundaries, without changing the wording. This applies to all summary, parameter, return, and raises sections.
- **Avoid examples in docstrings**: Keep docstrings concise and focused on what the function does, not how to use it
- **Block comments only when absolutely necessary**: Only use block comments to explain complex business logic or algorithms that cannot be made clear through code structure alone
- **Prefer refactoring over commenting**: If code needs a comment to be understood, consider refactoring it to be more self-explanatory instead

#### Example of Properly Wrapped Docstring
```python
def example_function(param1: int, param2: str) -> bool:
    """
    Short summary of what the function does, wrapped at 88 characters or less per line.

    Args:
        param1: Description of the first parameter, wrapped at 88 characters or less.
        param2: Description of the second parameter, wrapped at 88 characters or less.

    Returns:
        Description of the return value, wrapped at 88 characters or less.

    Raises:
        ValueError: Description of when this error is raised, wrapped at 88 characters.
    """
    # ...existing code...
```

### Imports
- **Keep imports at the top level**: All import statements must be at the module level, not inside functions or classes
- Group imports in the following order:
  1. Standard library imports
  2. Third-party library imports
  3. Local application/library imports
- Use absolute imports when possible

### Error Handling
- **Avoid catching broad Exception**: Don't use `except Exception:` or bare `except:`
- Catch specific exception types that you can handle appropriately
- **Let exceptions bubble up**: If you can't handle an exception meaningfully, let it propagate to the caller
- **Do not use logger unless explicitly required**: Avoid adding logging statements unless specifically requested or when updating existing code that already uses logging
- Only catch exceptions when you can:
  - Handle the error condition properly
  - Add meaningful context to the error
  - Log the error appropriately (only when logging is explicitly required)

### Example of Good Error Handling
```python
try:
    result = api_call()
except ValueError as e:
    raise
except ConnectionError as e:
    raise

# Bad - broad exception catching that hides important errors
try:
    result = api_call()
except Exception as e:
    pass
```

## Clean Code Guidelines
- Use meaningful variable and function names that express intent
- Keep functions small and focused on a single responsibility
- Follow the Single Responsibility Principle (SRP)
- Prefer composition over inheritance
- Write code that is easy to read and understand
- Avoid deep nesting - prefer early returns and guard clauses
- Use descriptive names over comments
- Keep classes small and cohesive
- Minimize dependencies between modules

## Configuration Management
- **Prefer environment variables**: Use environment variables for configuration values instead of hardcoded constants
- Store sensitive information (API keys, passwords, tokens) in environment variables, never in code
- Use environment variables for deployment-specific settings (URLs, ports, feature flags)
- Provide sensible defaults when environment variables are not set
- Document required environment variables in README or configuration files

### Example of Good Configuration Management


```python
from zola.utils.env import (
    get_env_str, get_env_bool, get_env_int, get_env_float, get_env_list, get_env_dict, get_env_json,
    get_env_path, get_env_url, get_env_enum, get_env_uuid, get_env_datetime, get_env_timedelta
)

API_BASE_URL = get_env_str('API_BASE_URL', 'https://api.example.com')
DATABASE_URL = get_env_str('DATABASE_URL', 'sqlite:///app.db')
DEBUG_MODE = get_env_bool('DEBUG', False)
MAX_RETRIES = get_env_int('MAX_RETRIES', 3)
TIMEOUT_SECONDS = get_env_float('TIMEOUT_SECONDS', 30.0)
ALLOWED_DOMAINS = get_env_list('ALLOWED_DOMAINS', [])
API_SETTINGS = get_env_dict('API_SETTINGS', {})
EXTRA_CONFIG = get_env_json('EXTRA_CONFIG', {})
DATA_PATH = get_env_path('DATA_PATH', '/data')
SERVICE_URL = get_env_url('SERVICE_URL', 'https://service.example.com')
# Example: get_env_enum('ENVIRONMENT', EnvironmentEnum, default=EnvironmentEnum.PROD)
# Example: get_env_uuid('INSTANCE_ID')
# Example: get_env_datetime('START_TIME')
# Example: get_env_timedelta('TIMEOUT_DELTA')

# Bad - hardcoded configuration values
API_BASE_URL = 'https://api.example.com'
DATABASE_URL = 'sqlite:///app.db'
DEBUG_MODE = True
```


## Additional Guidelines
- Follow PEP 8 style guidelines for Python code
- Write unit tests for new functionality
- Use type hints where appropriate
- Prefer explicit over implicit code
- Remove dead code and unused imports
- **Always run tests using the runTests tool, not the terminal or IDE**: Use the runTests tool to execute all tests. Do not use the terminal or IDE test runner for running tests.

---

## Systematic Approach for Copilot Tasks

Always assume the user wants you to start and complete a task. Stay on the task until it’s truly done. This means:

1. Implement the entire feature or fix the bug as requested.
2. Check for errors and resolve them.
3. Validate that the project builds and runs correctly.

Do **not** stop or hand control back until you are certain the fix is correct.

When asked to implement features, fix bugs, or modify code, follow this systematic approach:

### Code Analysis Phase
1. Understand the request: Break down what the user wants to achieve.
2. Explore the codebase: Use available tools to understand the project structure.
   - Use file and directory search tools to understand project layout.
   - Use semantic and grep search to find relevant code patterns.
   - Read key files to understand existing patterns.

### Implementation Strategy
3. Identify patterns: Look for existing code patterns, naming conventions, and architectural decisions.
4. Plan changes: Determine which files need modification and what changes are required.
5. Follow conventions: Match existing code style, import patterns, and component structure.

### Code Modification Phase
6. Make targeted edits: Use appropriate editing tools for precise changes.
   - Include 3-5 lines of unchanged code for context in replacements.
   - Use `// ...existing code...` comments to represent unchanged regions when needed.

### Quality Assurance
7. Validate changes: Check for errors after modifications.
8. Test understanding: Ensure changes integrate well with the existing codebase.
9. Update documentation: Modify relevant documentation to reflect changes made.

## Tool Usage Guidelines

1. Prefer reading the entire file if it is small (less than 2000 lines).
2. Use fetch tools to retrieve URLs provided by the user. If the content contains other URLs, continue fetching until you have sufficient context.
3. Always check for errors after making changes. Resolve all errors before handing control back to the user.

## Key Principles

- **Explore First**: Never make assumptions—examine the codebase to understand existing patterns.
- **Minimal Changes**: Make the smallest changes necessary to achieve the goal.
- **Consistency**: Follow existing naming conventions, file structure, and coding patterns.
- **Context Awareness**: Understand the project type, frameworks, and libraries in use.
- **Tool Selection**: Choose the most appropriate tool for each task (do not use terminal commands when editing tools exist).

## Communication

- Explain what you are doing and why.
- Show understanding of the existing codebase.
- Document learnings for future reference.
- Be concise but thorough in explanations.

Always start by gathering context about the codebase before making any changes. Use the available tools systematically to understand, plan, implement, and validate your changes.
