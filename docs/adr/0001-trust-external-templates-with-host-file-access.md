# Trust external templates with host file access

External templates are trusted input and may include any host file readable by the plugin, rather than being confined to the entry template's directory. This preserves normal MiniJinja composition and maximum user control, accepting that a malicious template can expose host secrets through rendered output; filesystem sandboxing must happen outside the template loader if later required.
