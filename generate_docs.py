#!/usr/bin/env python3
"""
TAC Documentation Generator
Generates HTML documentation for the TAC system by parsing EmmyLua annotations
"""

import re
import os
from pathlib import Path
from typing import List, Dict, Any

class TACDocGenerator:
    def __init__(self, input_dir: str, output_dir: str):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.modules = []
        
    def parse_file(self, filepath: Path) -> Dict[str, Any]:
        """Parse a Lua file and extract documentation"""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        module = {
            'name': str(filepath.relative_to(self.input_dir)).replace('.lua', '').replace('/', '.'),
            'filename': filepath.stem,
            'path': str(filepath.relative_to(self.input_dir)),
            'description': '',
            'examples': [],
            'functions': [],
            'version': None,
            'author': None,
            'license': None
        }
        
        # Extract author, license, version, and description from block comments first (takes precedence)
        block_match = re.search(r'--\[\[(.*?)\]\]', content, re.DOTALL)
        if block_match:
            block = block_match.group(1)
            
            # Extract version from @version tag
            version_match = re.search(r'@version\s+([^\n]+)', block)
            if version_match:
                module['version'] = version_match.group(1).strip()
            
            # Extract author
            author_match = re.search(r'@author\s+([^\n]+)', block)
            if author_match:
                module['author'] = author_match.group(1).strip()
            
            # Extract license
            license_match = re.search(r'@license\s+([^\n]+)', block)
            if license_match:
                module['license'] = license_match.group(1).strip()
            
            # Extract module description from block comment
            # Get all lines before the first @tag
            desc_lines = []
            in_description = False
            for line in block.split('\n'):
                line = line.strip()
                # Skip the first line if it's just a title
                if not in_description and line and not line.startswith('@'):
                    in_description = True
                    continue  # Skip title line
                if in_description:
                    if line.startswith('@'):
                        break
                    if line:  # Only add non-empty lines
                        desc_lines.append(line)
            module['description'] = ' '.join(desc_lines).strip()
        
        # If no @version tag found in block comment, try to extract version from code
        if not module['version']:
            version_match = re.search(r'version\s*=\s*["\']([^"\']+)["\']', content, re.IGNORECASE)
            if version_match:
                module['version'] = version_match.group(1)
        
        # If no block comment description, try to extract from --- comments
        if not module['description']:
            desc_lines = []
            for line in content.split('\n'):
                if line.startswith('---'):
                    cleaned = line[3:].strip()
                    if cleaned.startswith('@'):
                        break
                    if cleaned:
                        desc_lines.append(cleaned)
                elif desc_lines:
                    break
            module['description'] = ' '.join(desc_lines) if desc_lines else ''
        
        # Extract examples from @example in block comments
        if block_match:
            block = block_match.group(1)
            # Split on @example and process each part
            parts = re.split(r'@example\s*\n', block)
            for i, part in enumerate(parts):
                if i == 0:  # Skip the part before the first @example
                    continue
                # Extract text until next @ tag
                example_match = re.match(r'((?:(?!@(?:module|author|version|license)\b).*\n?)*)', part, re.MULTILINE | re.DOTALL)
                if example_match:
                    example_text = example_match.group(1)
                    if example_text.strip():
                        # Clean up leading whitespace while preserving relative indentation
                        lines = example_text.split('\n')
                        # Find minimum indentation (ignoring empty lines)
                        min_indent = float('inf')
                        for line in lines:
                            if line.strip():  # Only consider non-empty lines
                                indent = len(line) - len(line.lstrip())
                                min_indent = min(min_indent, indent)
                        # Remove minimum indentation from all lines
                        if min_indent != float('inf') and min_indent > 0:
                            cleaned_lines = []
                            for line in lines:
                                if len(line) >= min_indent:
                                    cleaned_lines.append(line[min_indent:])
                                else:
                                    cleaned_lines.append(line)
                        else:
                            cleaned_lines = lines
                        # Join and strip any leading/trailing empty lines
                        result = '\n'.join(cleaned_lines).strip()
                        if result:
                            module['examples'].append(result)
        
        # Also extract examples from @usage (for backward compatibility)
        usage_pattern = r'---@usage\s*\n((?:---[^@].*?\n)+)'
        for match in re.finditer(usage_pattern, content, re.MULTILINE):
            example_block = match.group(1)
            example_lines = []
            for line in example_block.split('\n'):
                if line.startswith('---'):
                    cleaned = line[3:]
                    if cleaned.startswith(' '):
                        cleaned = cleaned[1:]
                    if cleaned and not cleaned.lstrip().startswith('@'):
                        example_lines.append(cleaned)
            if example_lines:
                module['examples'].append('\n'.join(example_lines))
        
        # Extract functions (allow blank lines between docs and function, support both -- and --- style comments)
        func_pattern = r'((?:[ \t]*---?.*?\n)+)(?:[ \t]*\n)*[ \t]*(local\s+)?function\s+([\w.:]+)\s*\((.*?)\)'
        for match in re.finditer(func_pattern, content, re.MULTILINE):
            doc_block, is_local, func_name, params = match.groups()
            
            # Skip internal functions
            if is_local and '.' not in func_name and ':' not in func_name:
                continue
            if '_' in func_name and (func_name.startswith('_') or '._' in func_name):
                continue
            
            line_num = content[:match.start()].count('\n') + 1
            
            func_info = {
                'name': func_name,
                'params': [],
                'returns': '',
                'description': '',
                'line': line_num
            }
            
            # Parse documentation
            desc_lines = []
            for line in doc_block.split('\n'):
                line = line.strip()
                if line.startswith('---'):
                    line = line[3:].strip()
                elif line.startswith('--'):
                    line = line[2:].strip()
                else:
                    continue
                    
                if line.startswith('@param'):
                    param_match = re.match(r'@param\s+(\w+\??)\s+(\S+)(?:\s+(.+))?', line)
                    if param_match:
                        func_info['params'].append({
                            'name': param_match.group(1),
                            'type': param_match.group(2),
                            'description': param_match.group(3) or ''
                        })
                elif line.startswith('@return'):
                    func_info['returns'] = line.replace('@return', '').strip()
                elif not line.startswith('@'):
                    desc_lines.append(line)
            
            func_info['description'] = ' '.join(desc_lines)
            if func_info['description'] or func_info['params'] or func_info['returns']:
                module['functions'].append(func_info)
        
        return module
    
    def generate_html_module(self, module: Dict[str, Any]) -> str:
        """Generate HTML documentation for a module"""
        description = module['description'].replace('<', '&lt;').replace('>', '&gt;')
        github_url = f"https://github.com/Twijn/tac/blob/main/{module['path']}"
        
        version_badge = f' <span class="version-badge">v{module["version"]}</span>' if module.get('version') else ''
        
        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{module['name']} - TAC Documentation</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
    <style>
        :root {{
            --bg: #ffffff;
            --text: #1a1a1a;
            --link: #0066cc;
            --border: #e0e0e0;
            --code-bg: #f5f5f5;
        }}
        @media (prefers-color-scheme: dark) {{
            :root {{
                --bg: #1a1a1a;
                --text: #e0e0e0;
                --link: #4d9fff;
                --border: #333333;
                --code-bg: #2a2a2a;
            }}
        }}
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            padding: 2rem;
            max-width: 1200px;
            margin: 0 auto;
        }}
        .header {{
            border-bottom: 2px solid var(--border);
            padding-bottom: 1.5rem;
            margin-bottom: 2rem;
        }}
        .header h1 {{
            margin-bottom: 1rem;
            font-size: 2.5rem;
        }}
        .header p {{
            font-size: 1.1rem;
            line-height: 1.8;
            opacity: 0.9;
        }}
        .metadata {{
            font-size: 0.9rem;
            opacity: 0.8;
            margin-top: 0.5rem;
        }}
        h2 {{
            margin-top: 3rem;
            margin-bottom: 1.5rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.8rem;
        }}
        h3 {{
            margin-top: 1.5rem;
            margin-bottom: 0.75rem;
            font-size: 1.3rem;
        }}
        code {{
            background: var(--code-bg);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{
            padding: 1rem;
            border-radius: 4px;
            overflow-x: auto;
            margin: 1rem 0;
            border: 1px solid var(--border);
        }}
        pre code {{
            background: none;
            padding: 0;
            font-size: 0.95em;
        }}
        .function:not(.token) {{
            margin: 2rem 0;
            padding: 1.5rem;
            border: 1px solid var(--border);
            border-radius: 6px;
        }}
        .function h3 {{
            margin-top: 0;
        }}
        .function > p {{
            margin: 1rem 0;
            line-height: 1.7;
        }}
        .params, .returns {{
            margin-top: 1rem;
        }}
        .params ul, .returns ul {{
            list-style: none;
            padding-left: 0;
        }}
        .params li, .returns li {{
            padding: 0.5rem 0;
            padding-left: 1rem;
            border-left: 3px solid var(--border);
            margin: 0.25rem 0;
        }}
        a {{
            color: var(--link);
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        .back-link {{
            margin-bottom: 1.5rem;
            font-size: 0.95rem;
        }}
        .version-badge {{
            display: inline-block;
            background: #2a3540;
            color: #8b949e;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.75em;
            font-weight: 500;
            margin-left: 1rem;
            vertical-align: middle;
        }}
        .github-link {{
            display: inline-block;
            padding: 0.5rem 1rem;
            background: var(--link);
            color: white;
            border: 1px solid var(--link);
            border-radius: 4px;
            text-decoration: none;
            font-size: 0.9em;
            transition: all 0.2s;
            margin-top: 1rem;
        }}
        .github-link:hover {{
            opacity: 0.85;
            text-decoration: none;
        }}
    </style>
</head>
<body>
    <div class="back-link"><a href="index.html">← Back to index</a></div>
    <div class="header">
        <h1>{module['name']}{version_badge}</h1>
        <p>{description}</p>
"""
        
        if module.get('author') or module.get('license'):
            html += "        <div class='metadata'>"
            if module.get('author'):
                html += f" Author: {module['author']}"
            if module.get('license'):
                html += f" • License: {module['license']}"
            html += "</div>\n"
        
        html += f"""        <a href="{github_url}" class="github-link" target="_blank">View on GitHub →</a>
    </div>
"""
        
        # Examples
        if module['examples']:
            html += "    <h2>Examples</h2>\n"
            for example in module['examples']:
                escaped = example.replace('<', '&lt;').replace('>', '&gt;')
                html += f"    <pre><code class='language-lua'>{escaped}</code></pre>\n"
        
        # Functions
        if module['functions']:
            html += "    <h2>Functions</h2>\n"
            for func in module['functions']:
                html += "    <div class='function'>\n"
                params_str = ', '.join([p['name'] for p in func['params']])
                html += f"        <h3><code>{func['name']}({params_str})</code></h3>\n"
                
                func_github_url = f"{github_url}#L{func.get('line', 1)}"
                html += f"        <a href='{func_github_url}' target='_blank' style='font-size: 0.85em; opacity: 0.7;'>View source</a>\n"
                
                if func['description']:
                    html += f"        <p>{func['description']}</p>\n"
                
                if func['params']:
                    html += "        <div class='params'>\n"
                    html += "            <strong>Parameters:</strong>\n"
                    html += "            <ul>\n"
                    for param in func['params']:
                        html += f"                <li><code>{param['name']}</code> ({param['type']})"
                        if param['description']:
                            html += f": {param['description']}"
                        html += "</li>\n"
                    html += "            </ul>\n"
                    html += "        </div>\n"
                
                if func['returns']:
                    html += f"        <div class='returns'><strong>Returns:</strong> {func['returns']}</div>\n"
                
                html += "    </div>\n"
        
        html += """</body>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-lua.min.js"></script>
</html>
"""
        return html
    
    def generate_html_index(self, modules: List[Dict[str, Any]]) -> str:
        """Generate HTML index page"""
        html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TAC Documentation</title>
    <style>
        :root {
            --bg: #ffffff;
            --text: #1a1a1a;
            --link: #0066cc;
            --border: #e0e0e0;
            --code-bg: #f5f5f5;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1a1a1a;
                --text: #e0e0e0;
                --link: #4d9fff;
                --border: #333333;
                --code-bg: #2a2a2a;
            }
        }
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            padding: 2rem;
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid var(--border);
        }
        h2 {
            margin-top: 2rem;
            margin-bottom: 1rem;
        }
        .module {
            padding: 1rem;
            margin: 0.5rem 0;
            border: 1px solid var(--border);
            border-radius: 4px;
        }
        .module h3 {
            margin: 0 0 0.5rem 0;
        }
        .module p {
            opacity: 0.8;
        }
        a {
            color: var(--link);
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .version-badge {
            display: inline-block;
            background: #2a3540;
            color: #8b949e;
            padding: 0.15rem 0.4rem;
            border-radius: 3px;
            font-size: 0.7em;
            font-weight: 500;
            margin-left: 0.5rem;
            vertical-align: middle;
        }
        .install-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 8px;
            padding: 2rem;
            margin: 2rem 0;
            color: white;
        }
        .install-box h2 {
            margin-top: 0;
            color: white;
            border: none;
        }
        .install-box p {
            opacity: 0.95;
            margin-bottom: 1rem;
        }
        .install-command {
            position: relative;
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 6px;
            padding: 1rem 1.5rem;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 1rem;
            margin: 1rem 0;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 1rem;
            flex-wrap: wrap;
        }
        .install-command code {
            background: none;
            color: #fff;
            padding: 0;
            font-size: 1em;
            word-break: break-all;
            flex: 1;
            min-width: 0;
        }
        .copy-button {
            background: rgba(255, 255, 255, 0.2);
            border: 1px solid rgba(255, 255, 255, 0.3);
            color: white;
            padding: 0.5rem 1rem;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 500;
            transition: all 0.2s;
            white-space: nowrap;
            flex-shrink: 0;
        }
        .copy-button:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-1px);
        }
        .copy-button:active {
            transform: translateY(0);
        }
        .copy-button.copied {
            background: rgba(76, 175, 80, 0.8);
            border-color: rgba(76, 175, 80, 1);
        }
        @media (max-width: 768px) {
            .install-box {
                padding: 1.5rem;
                margin: 1.5rem 0;
            }
            .install-command {
                padding: 0.75rem 1rem;
                font-size: 0.85rem;
                flex-direction: column;
                align-items: stretch;
            }
            .install-command code {
                font-size: 0.85em;
                margin-bottom: 0.5rem;
            }
            .copy-button {
                width: 100%;
                text-align: center;
            }
        }
        @media (max-width: 480px) {
            .install-box {
                padding: 1rem;
                margin: 1rem 0;
            }
            .install-command {
                padding: 0.5rem 0.75rem;
                font-size: 0.75rem;
            }
            .install-command code {
                font-size: 0.75em;
            }
        }
    </style>
</head>
<body>
    <h1>TAC Documentation</h1>
    <p>Terminal Access Control (TAC) is a comprehensive access control system for ComputerCraft that provides card-based authentication, extensible modules, and integration with external services.</p>
    
    <div class="install-box">
        <h2>Quick Install</h2>
        <p>Get started with TAC in seconds! Run this command in ComputerCraft:</p>
        <div class="install-command">
            <code>wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua</code>
            <button class="copy-button" onclick="copyInstallCommand(this)">Copy</button>
        </div>
        <p style="font-size: 0.9rem; opacity: 0.8; margin-top: 0.5rem;">This will download and run the TAC installer, which will guide you through the setup process.</p>
    </div>
    
"""
        
        # Categorize and organize modules hierarchically
        categories = {
            'Core Modules': [m for m in modules if m['path'].startswith('tac/core/') and '/' not in m['path'][9:]],
            'Library Modules': [m for m in modules if m['path'].startswith('tac/lib/')],
            'Extension Modules': [],
            'Command Modules': [m for m in modules if m['path'].startswith('tac/commands/')],
        }
        
        # Organize extension modules hierarchically
        extension_parents = {}
        extension_children = {}
        
        for m in modules:
            if m['path'].startswith('tac/extensions/'):
                path_parts = m['path'][15:].split('/')  # Remove 'tac/extensions/'
                if len(path_parts) == 1:
                    # Top-level extension file (parent)
                    # e.g., shopk_access.lua -> tac.extensions.shopk_access
                    base_name = path_parts[0].replace('.lua', '')
                    extension_name = f"tac.extensions.{base_name}"
                    extension_parents[extension_name] = m
                    if extension_name not in extension_children:
                        extension_children[extension_name] = []
                elif len(path_parts) == 2:
                    # Submodule (child)
                    # e.g., shopk_access/commands.lua -> parent is tac.extensions.shopk_access
                    parent_name = f"tac.extensions.{path_parts[0]}"
                    if parent_name not in extension_children:
                        extension_children[parent_name] = []
                    extension_children[parent_name].append(m)
        
        # Sort parents and their children
        sorted_parents = sorted(extension_parents.items(), key=lambda x: x[0])
        
        # Add other modules
        categorized = categories['Core Modules'] + categories['Command Modules'] + list(extension_parents.values())
        for children in extension_children.values():
            categorized.extend(children)
        other = [m for m in modules if m not in categorized]
        if other:
            categories['Other Modules'] = other
        
        for category, mods in categories.items():
            if category == 'Extension Modules':
                continue  # Handle extensions separately
            if not mods:
                continue
            html += f"    <h2>{category}</h2>\n"
            for module in mods:
                version_badge = f'<span class="version-badge">v{module["version"]}</span>' if module.get('version') else ''
                desc = module['description'][:200] + ('...' if len(module['description']) > 200 else '')
                html += f"""    <div class="module">
        <h3><a href="{module['name'].replace('.', '_')}.html">{module['name']}</a>{version_badge}</h3>
        <p>{desc}</p>
    </div>
"""
        
        # Handle extension modules with hierarchy
        if sorted_parents:
            html += f"    <h2>Extension Modules</h2>\n"
            for parent_name, parent_module in sorted_parents:
                version_badge = f'<span class="version-badge">v{parent_module["version"]}</span>' if parent_module.get('version') else ''
                desc = parent_module['description'][:200] + ('...' if len(parent_module['description']) > 200 else '')
                html += f"""    <div class="module">
        <h3><a href="{parent_module['name'].replace('.', '_')}.html">{parent_module['name']}</a>{version_badge}</h3>
        <p>{desc}</p>
"""
                # Add children
                children = extension_children.get(parent_name, [])
                if children:
                    html += '        <div style="margin-left: 2rem; margin-top: 0.75rem; border-left: 2px solid var(--border); padding-left: 1rem;">\n'
                    for child in sorted(children, key=lambda x: x['name']):
                        child_desc = child['description'][:150] + ('...' if len(child['description']) > 150 else '')
                        html += f"""            <div style="margin: 0.5rem 0;">
                <strong><a href="{child['name'].replace('.', '_')}.html">{child['name'].split('.')[-1]}</a></strong>
                <span style="opacity: 0.7; font-size: 0.9em;"> - {child_desc}</span>
            </div>
"""
                    html += '        </div>\n'
                html += '    </div>\n'
        
        html += """</body>
<script>
function copyInstallCommand(button) {
    const command = 'wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua';
    navigator.clipboard.writeText(command).then(() => {
        const originalText = button.textContent;
        button.textContent = 'Copied!';
        button.classList.add('copied');
        setTimeout(() => {
            button.textContent = originalText;
            button.classList.remove('copied');
        }, 2000);
    }).catch(err => {
        console.error('Failed to copy:', err);
        alert('Failed to copy to clipboard');
    });
}
</script>
</html>
"""
        return html
    
    def generate_api_endpoints(self):
        """Generate JSON API endpoints for version checking and updates"""
        import json
        import glob
        
        # Create API directory
        api_dir = self.output_dir / 'api'
        api_dir.mkdir(exist_ok=True)
        
        # Extract core TAC version
        tac_version = None
        tac_module = None
        for m in self.modules:
            if m['name'] == 'tac.init':
                tac_version = m.get('version', '0.0.0')
                tac_module = m
                break
        
        # Build versions manifest
        versions = {
            'tac': {
                'version': tac_version or '0.0.0',
                'init': {
                    'version': tac_version or '0.0.0',
                    'path': 'tac/init.lua',
                    'download_url': 'https://raw.githubusercontent.com/Twijn/tac/main/tac/init.lua'
                },
                'core': {},
                'lib': {},
                'commands': {},
                'extensions': {}
            }
        }
        
        # Categorize modules
        for m in self.modules:
            if m['path'].startswith('tac/core/'):
                module_name = m['name'].replace('tac.core.', '')
                versions['tac']['core'][module_name] = {
                    'version': m.get('version', '0.0.0'),
                    'path': m['path'],
                    'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{m['path']}"
                }
            elif m['path'].startswith('tac/lib/'):
                module_name = m['name'].replace('tac.lib.', '')
                versions['tac']['lib'][module_name] = {
                    'version': m.get('version', '0.0.0'),
                    'path': m['path'],
                    'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{m['path']}"
                }
            elif m['path'].startswith('tac/commands/'):
                module_name = m['name'].replace('tac.commands.', '')
                versions['tac']['commands'][module_name] = {
                    'version': m.get('version', '0.0.0'),
                    'path': m['path'],
                    'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{m['path']}"
                }
            elif m['path'].startswith('tac/extensions/'):
                # Only include top-level extensions (not submodules)
                if '/' not in m['path'][15:]:
                    module_name = m['name'].replace('tac.extensions.', '')
                    versions['tac']['extensions'][module_name] = {
                        'version': m.get('version', '0.0.0'),
                        'path': m['path'],
                        'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{m['path']}"
                    }
        
        # Also scan tac/commands directory directly for any files not in parsed modules
        commands_dir = self.input_dir / 'tac' / 'commands'
        if commands_dir.exists():
            for cmd_file in commands_dir.glob('*.lua'):
                cmd_name = cmd_file.stem
                if cmd_name not in versions['tac']['commands']:
                    versions['tac']['commands'][cmd_name] = {
                        'version': '0.0.0',
                        'path': f'tac/commands/{cmd_file.name}',
                        'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/tac/commands/{cmd_file.name}"
                    }
        
        # Write versions.json
        with open(api_dir / 'versions.json', 'w') as f:
            json.dump(versions, f, indent=2)
        
        # Write latest.json (just the TAC version)
        latest = {
            'version': tac_version or '0.0.0',
            'updated_at': os.popen('date -u +"%Y-%m-%dT%H:%M:%SZ"').read().strip()
        }
        with open(api_dir / 'latest.json', 'w') as f:
            json.dump(latest, f, indent=2)
        
        # Write module manifests for each extension
        for m in self.modules:
            if m['path'].startswith('tac/extensions/') and '/' not in m['path'][15:]:
                module_name = m['name'].replace('tac.extensions.', '')
                
                # Find all submodules for this extension
                submodules = []
                extension_dir = m['path'].replace('.lua', '')
                for sub_m in self.modules:
                    if sub_m['path'].startswith(extension_dir + '/'):
                        submodules.append({
                            'name': sub_m['name'].split('.')[-1],
                            'path': sub_m['path'],
                            'version': sub_m.get('version'),
                            'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{sub_m['path']}"
                        })
                
                module_manifest = {
                    'name': module_name,
                    'version': m.get('version', '0.0.0'),
                    'description': m.get('description', ''),
                    'author': m.get('author'),
                    'main_file': m['path'],
                    'download_url': f"https://raw.githubusercontent.com/Twijn/tac/main/{m['path']}",
                    'submodules': submodules if submodules else None
                }
                
                with open(api_dir / f'{module_name}.json', 'w') as f:
                    json.dump(module_manifest, f, indent=2)
        
        print(f"Generated API endpoints in {api_dir}")
    
    def generate(self):
        """Generate documentation for all Lua files"""
        self.output_dir.mkdir(exist_ok=True, parents=True)
        
        # Find all Lua files (excluding data, test directories)
        lua_files = []
        for ext in ['*.lua']:
            lua_files.extend(self.input_dir.rglob(ext))
        
        # Filter out unwanted files
        # Note: We INCLUDE tac/lib/ but exclude top-level lib/ (which has separate docs at ccmisc.twijn.dev)
        filtered_files = []
        for f in lua_files:
            rel_path = str(f.relative_to(self.input_dir))
            # Skip data/, test/, .git
            if any(skip in rel_path for skip in ['data/', 'test/', '.git']):
                continue
            # Skip top-level lib/ but NOT tac/lib/
            if rel_path.startswith('lib/') and not rel_path.startswith('tac/lib/'):
                continue
            filtered_files.append(f)
        lua_files = filtered_files
        
        # Parse each file
        for lua_file in sorted(lua_files):
            try:
                module = self.parse_file(lua_file)
                if module['description'] or module['functions']:
                    self.modules.append(module)
                    
                    # Generate HTML
                    html_content = self.generate_html_module(module)
                    html_filename = module['name'].replace('.', '_') + '.html'
                    with open(self.output_dir / html_filename, 'w', encoding='utf-8') as f:
                        f.write(html_content)
            except Exception as e:
                print(f"Error processing {lua_file}: {e}")
        
        # Generate index
        index_html = self.generate_html_index(self.modules)
        with open(self.output_dir / 'index.html', 'w', encoding='utf-8') as f:
            f.write(index_html)
        
        # Generate API endpoints
        self.generate_api_endpoints()
        
        print(f"Generated documentation for {len(self.modules)} modules")
        print(f"Output directory: {self.output_dir}")

if __name__ == '__main__':
    base_path = Path(__file__).parent
    print("TAC Documentation Generator")
    print("=" * 40)
    print(f"Base path: {base_path}")
    print()
    
    generator = TACDocGenerator(str(base_path), str(base_path / 'docs'))
    
    print("Parsing Lua files...")
    generator.generate()
    
    print()
    print("Done! Documentation is available in the docs/ directory.")
    print("Open docs/index.html in your browser to get started.")
