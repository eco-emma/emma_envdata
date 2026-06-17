# Terminal Command Robustness Rules

## The core problem

Commands that produce **no output** (empty stdout/stderr) cause Cline to hang
waiting for output that never arrives. This happens most often with:

- `cat` on binary or near-empty files
- `od`, `xxd`, `python3 -c "..."` with single-quoted strings containing
  apostrophes (shell quoting breaks silently)
- Long pipelines where an intermediate command swallows all output
- Any command whose output is purely non-printable bytes

## Rules to follow

### 1. Always append `; echo "EXIT:$?"` to commands that might produce no output

```bash
cat somefile.md; echo "EXIT:$?"
```

This guarantees at least one line of output so Cline never hangs.

### 2. Prefer `grep -P` or `grep -a` when scanning binary/mixed files

```bash
grep -a "pattern" file.bin; echo "done"
```

### 3. Use `head -c 200` when inspecting unknown files

```bash
cat unknownfile | head -c 200; echo "done"
```

### 4. Avoid `python3 -c '...'` with complex quoting

Use a heredoc or a temp script file instead:

```bash
python3 << 'EOF'
data = open('/path/to/file', 'rb').read()
print('bytes:', len(data))
EOF
echo "done"
```

### 5. Avoid `od -c` on large files without `head`

```bash
od -c file | head -20; echo "done"
```

### 6. Never run interactive commands

Always pass `-y`, `--no-pager`, `--batch`, or equivalent flags.
Redirect stderr: `command 2>&1`.

### 7. Timeout guard for R commands

Prefix long R invocations with a timeout:

```bash
timeout 60 Rscript -e "..." 2>&1; echo "EXIT:$?"
```

### 8. When a command returns no output, do NOT retry the same command

If a command produces no output, assume it succeeded silently and move on.
Do not loop or retry — that causes the hang to repeat.

## Summary

**Every `execute_command` call must produce at least one line of output.**
Append `; echo "done"` or `; echo "EXIT:$?"` to any command that might be silent.
