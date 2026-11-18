// Mirrored by native ShortcutRules. Fixed Autocomplete Everywhere actions cannot be reassigned;
// extra modifiers remain available for configurable shortcuts.
export function isReservedShortcut(binding: { keyCode: number; modifiers: number }): boolean {
  return binding.modifiers === 2048 && [48, 125, 126, 18, 19, 20, 21, 23, 22, 26, 28, 25].includes(binding.keyCode);
}
