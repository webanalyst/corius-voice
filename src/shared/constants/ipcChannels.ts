// IPC Channel names for communication between main and renderer processes

export const IPC_CHANNELS = {
  // Recording control
  RECORDING_START: 'recording:start',
  RECORDING_STOP: 'recording:stop',
  RECORDING_STATE_CHANGED: 'recording:state-changed',

  // Transcription events
  TRANSCRIPTION_INTERIM: 'transcription:interim',
  TRANSCRIPTION_FINAL: 'transcription:final',
  TRANSCRIPTION_ERROR: 'transcription:error',

  // Audio data for visualizer
  AUDIO_DATA: 'audio:data',
  AUDIO_LEVEL: 'audio:level',

  // Flow bar control
  FLOWBAR_SHOW: 'flowbar:show',
  FLOWBAR_HIDE: 'flowbar:hide',
  FLOWBAR_UPDATE: 'flowbar:update',

  // Store operations
  STORE_GET: 'store:get',
  STORE_SET: 'store:set',
  STORE_DELETE: 'store:delete',

  // Transcription history
  HISTORY_GET: 'history:get',
  HISTORY_ADD: 'history:add',
  HISTORY_DELETE: 'history:delete',
  HISTORY_CLEAR: 'history:clear',

  // Dictionary operations
  DICTIONARY_GET: 'dictionary:get',
  DICTIONARY_ADD: 'dictionary:add',
  DICTIONARY_UPDATE: 'dictionary:update',
  DICTIONARY_DELETE: 'dictionary:delete',

  // Snippets operations
  SNIPPETS_GET: 'snippets:get',
  SNIPPETS_ADD: 'snippets:add',
  SNIPPETS_UPDATE: 'snippets:update',
  SNIPPETS_DELETE: 'snippets:delete',

  // Notes operations
  NOTES_GET: 'notes:get',
  NOTES_ADD: 'notes:add',
  NOTES_DELETE: 'notes:delete',

  // Settings
  SETTINGS_GET: 'settings:get',
  SETTINGS_SET: 'settings:set',

  // System
  APP_QUIT: 'app:quit',
  APP_MINIMIZE: 'app:minimize',
  APP_MAXIMIZE: 'app:maximize',
  OPEN_EXTERNAL: 'open:external',

  // Clipboard
  CLIPBOARD_WRITE: 'clipboard:write',
  CLIPBOARD_PASTE: 'clipboard:paste',

  // Permissions
  PERMISSION_CHECK: 'permission:check',
  PERMISSION_REQUEST: 'permission:request'
} as const

export type IpcChannel = typeof IPC_CHANNELS[keyof typeof IPC_CHANNELS]
