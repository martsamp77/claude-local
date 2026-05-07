// ============================================================
// local-additions.nss -- Marty's Nilesoft customizations
// Iteration 3: + per-extension editor launchers
// ============================================================

// 1. Shift-reveal power menu -- hidden until Shift held
menu(title="Power" vis=key.shift())
{
	item(title="Reload Shell config" cmd='@app.reload')
	item(title="Edit shell.nss" admin cmd='code' args='"@app.cfg"')
	item(title="Open install dir" cmd='"@app.dir"')
	item(title="Show shell.log" cmd='code' args='"@app.dir\shell.log"')
	separator
	item(title="Restart Explorer" admin cmd=command.restart_explorer)
	item(title="Nilesoft "+@app.ver vis=label)
}

// 2. Multi-format path copy -- top-level
menu(where=sel.count>0 type='file|dir|drive|namespace' title="Copy path" image=icon.copy_path)
{
	item(where=sel.count > 1 title="All paths (newline-joined)" cmd=command.copy(sel(false, "\n")))
	item(where=sel.count > 1 title="All paths (semicolon-joined)" cmd=command.copy(sel(false, ";")))
	item(mode="single" title=@sel.path cmd=command.copy(sel.path))
	separator
	item(mode="single" where=@sel.parent.len>3 title="Parent: "+@sel.parent cmd=command.copy(sel.parent))
	item(mode="single" type='file|dir|back.dir' title="Name: "+@sel.file.name cmd=command.copy(sel.file.name))
	item(mode="single" type='file' where=sel.file.ext.len>0 title="Extension: "+@sel.file.ext cmd=command.copy(sel.file.ext))
}

// 3. Per-extension editor launchers
menu(type='file' find='.md|.markdown' title="Markdown")
{
	item(title="Preview in VS Code" cmd='code' args='--goto "@sel.path:1" --command markdown.showPreview')
	item(title="Open in VS Code" cmd='code' args='"@sel.path"')
}

menu(type='file' find='.html|.htm' title="HTML")
{
	item(title="Open in default browser" cmd='"@sel.path"')
	item(title="Open in VS Code" cmd='code' args='"@sel.path"')
}

menu(type='file' find='.json' title="JSON")
{
	item(title="Open in VS Code" cmd='code' args='"@sel.path"')
}

menu(type='file' find='.py' title="Python")
{
	item(title="Run with Python" cmd-line='/K python "@sel.path"')
	item(title="Open in VS Code" cmd='code' args='"@sel.path"')
}

menu(type='file' find='.ps1' title="PowerShell")
{
	item(title="Run in pwsh" cmd='pwsh.exe' args='-NoProfile -File "@sel.path"')
	item(title="Run elevated" admin cmd='pwsh.exe' args='-NoProfile -File "@sel.path"')
	item(title="Open in VS Code" cmd='code' args='"@sel.path"')
}
