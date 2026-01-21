import React from 'react'
import { NavLink } from 'react-router-dom'
import {
  Home,
  BookOpen,
  Zap,
  Palette,
  FileText,
  Settings,
  Mic
} from 'lucide-react'
import { cn } from '../../lib/utils'

const navItems = [
  { to: '/', icon: Home, label: 'Home' },
  { to: '/dictionary', icon: BookOpen, label: 'Dictionary' },
  { to: '/snippets', icon: Zap, label: 'Snippets' },
  { to: '/style', icon: Palette, label: 'Style' },
  { to: '/notes', icon: FileText, label: 'Notes' },
  { to: '/settings', icon: Settings, label: 'Settings' }
]

export function Sidebar() {
  return (
    <aside className="flex h-full w-64 flex-col border-r border-sidebar-border bg-sidebar">
      {/* Drag region for window - space for traffic lights */}
      <div className="drag-region h-14 flex items-end pb-2 px-4">
        <div className="no-drag flex items-center gap-2 pl-16">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary">
            <Mic className="h-3.5 w-3.5 text-primary-foreground" />
          </div>
          <span className="font-semibold text-sidebar-foreground text-sm">Corius Voice</span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-1 px-3 py-4">
        {navItems.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-sidebar-accent text-sidebar-foreground'
                  : 'text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-foreground'
              )
            }
          >
            <Icon className="h-4 w-4" />
            {label}
          </NavLink>
        ))}
      </nav>

      {/* Footer */}
      <div className="border-t border-sidebar-border p-4">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>Option+Space to record</span>
        </div>
      </div>
    </aside>
  )
}
