#!/bin/bash

# Debugging information
echo "=== Current directory ==="
pwd
echo -e "\n=== Spec directory contents ==="
ls -la spec/

# Verify spec_helper.rb exists and has content
if [ ! -f "spec/spec_helper.rb" ]; then
  echo "Error: spec/spec_helper.rb is missing"
  exit 1
fi

echo -e "\n=== spec_helper.rb contents ==="
cat spec/spec_helper.rb

# Run tests with full path to spec_helper
echo -e "\n=== Running tests ==="
bundle exec rspec --require ./spec/spec_helper.rb spec/

exit_code=$?

# If the above fails, try an alternative approach
if [ $exit_code -ne 0 ]; then
  echo -e "\n=== First attempt failed, trying alternative approach ==="
  cd spec && bundle exec rspec --require ./spec_helper.rb
  exit_code=$?
fi

exit $exit_code
