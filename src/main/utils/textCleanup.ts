import { FILLER_WORDS } from '../../shared/constants/defaults'
import { getDictionary, getSnippets } from '../services/store.service'

/**
 * Clean transcribed text by removing filler words, applying dictionary
 * replacements, and expanding snippets.
 */
export function cleanText(text: string): string {
  if (!text.trim()) return ''

  let cleaned = text

  // Step 1: Remove filler words (sounds first, then language-specific)
  cleaned = removeFillerWords(cleaned, FILLER_WORDS.sounds)
  cleaned = removeFillerWords(cleaned, FILLER_WORDS.spanish)
  cleaned = removeFillerWords(cleaned, FILLER_WORDS.english)

  // Step 2: Apply dictionary replacements
  cleaned = applyDictionary(cleaned)

  // Step 3: Apply snippet expansions
  cleaned = applySnippets(cleaned)

  // Step 4: Clean up whitespace
  cleaned = normalizeWhitespace(cleaned)

  // Step 5: Fix capitalization after sentence-ending punctuation
  cleaned = fixCapitalization(cleaned)

  return cleaned.trim()
}

/**
 * Remove filler words from text
 */
function removeFillerWords(text: string, fillerWords: string[]): string {
  let result = text

  for (const filler of fillerWords) {
    // Create regex that matches the filler word as a whole word
    // Case insensitive, handles punctuation
    const escapedFiller = filler.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const regex = new RegExp(
      `(?:^|\\s)${escapedFiller}(?=[\\s.,!?;:]|$)`,
      'gi'
    )
    result = result.replace(regex, ' ')
  }

  return result
}

/**
 * Apply dictionary replacements (custom word corrections)
 */
function applyDictionary(text: string): string {
  const dictionary = getDictionary()
  let result = text

  for (const entry of dictionary) {
    if (!entry.enabled) continue

    // Match whole words only, case insensitive
    const escapedOriginal = entry.original.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const regex = new RegExp(`\\b${escapedOriginal}\\b`, 'gi')
    result = result.replace(regex, entry.replacement)
  }

  return result
}

/**
 * Apply snippet expansions (trigger -> content)
 */
function applySnippets(text: string): string {
  const snippets = getSnippets()
  let result = text

  for (const snippet of snippets) {
    if (!snippet.enabled) continue

    // Match trigger word exactly
    const escapedTrigger = snippet.trigger.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const regex = new RegExp(`\\b${escapedTrigger}\\b`, 'gi')
    result = result.replace(regex, snippet.content)
  }

  return result
}

/**
 * Normalize multiple spaces to single space
 */
function normalizeWhitespace(text: string): string {
  return text
    .replace(/\s+/g, ' ')           // Multiple spaces to single
    .replace(/\s+([.,!?;:])/g, '$1') // Remove space before punctuation
    .replace(/([.,!?;:])\s*/g, '$1 ') // Ensure single space after punctuation
    .trim()
}

/**
 * Fix capitalization after sentence-ending punctuation
 */
function fixCapitalization(text: string): string {
  // Capitalize first letter
  let result = text.charAt(0).toUpperCase() + text.slice(1)

  // Capitalize after sentence-ending punctuation
  result = result.replace(/([.!?]\s+)([a-z])/g, (_, punctuation, letter) => {
    return punctuation + letter.toUpperCase()
  })

  return result
}

/**
 * Detect if text is primarily Spanish or English
 */
export function detectLanguage(text: string): 'es' | 'en' {
  const spanishIndicators = [
    'el', 'la', 'los', 'las', 'un', 'una', 'que', 'de', 'en', 'por',
    'para', 'con', 'no', 'es', 'del', 'al', 'ser', 'estar', 'tiene',
    'hace', 'puede', 'como', 'pero', 'más', 'este', 'esta', 'esto'
  ]

  const englishIndicators = [
    'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
    'could', 'should', 'may', 'might', 'must', 'shall', 'can'
  ]

  const words = text.toLowerCase().split(/\s+/)

  let spanishScore = 0
  let englishScore = 0

  for (const word of words) {
    if (spanishIndicators.includes(word)) spanishScore++
    if (englishIndicators.includes(word)) englishScore++
  }

  return spanishScore > englishScore ? 'es' : 'en'
}
