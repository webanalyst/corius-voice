import React from 'react'
import { Routes, Route } from 'react-router-dom'
import { MainLayout } from './components/layout/MainLayout'
import { HomePage } from './pages/HomePage'
import { DictionaryPage } from './pages/DictionaryPage'
import { SnippetsPage } from './pages/SnippetsPage'
import { StylePage } from './pages/StylePage'
import { NotesPage } from './pages/NotesPage'
import { SettingsPage } from './pages/SettingsPage'

export default function App() {
  return (
    <MainLayout>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/dictionary" element={<DictionaryPage />} />
        <Route path="/snippets" element={<SnippetsPage />} />
        <Route path="/style" element={<StylePage />} />
        <Route path="/notes" element={<NotesPage />} />
        <Route path="/settings" element={<SettingsPage />} />
      </Routes>
    </MainLayout>
  )
}
