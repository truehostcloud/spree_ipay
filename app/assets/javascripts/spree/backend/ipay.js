// Add debounce to the global scope
document.addEventListener('DOMContentLoaded', function() {
  if (typeof window.debounce === 'undefined') {
    window.debounce = function(fn, wait) {
      let timeout;
      return function() {
        const context = this, args = arguments;
        clearTimeout(timeout);
        timeout = setTimeout(() => fn.apply(context, args), wait);
      };
    };
    console.log('iPay: Debounce function added to window object');
  }
});
