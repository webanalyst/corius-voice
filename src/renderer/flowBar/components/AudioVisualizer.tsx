import React, { useRef, useEffect } from 'react'

interface AudioVisualizerProps {
  levels: number[]
  barCount?: number
  barWidth?: number
  barGap?: number
  minHeight?: number
  maxHeight?: number
  color?: string
}

export function AudioVisualizer({
  levels,
  barCount = 32,
  barWidth = 3,
  barGap = 2,
  minHeight = 4,
  maxHeight = 40,
  color = '#ffffff'
}: AudioVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const animationRef = useRef<number>()
  const currentLevelsRef = useRef<number[]>(new Array(barCount).fill(0))

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Set canvas size
    const totalWidth = barCount * (barWidth + barGap) - barGap
    canvas.width = totalWidth
    canvas.height = maxHeight

    const animate = () => {
      // Smooth interpolation towards target levels
      const targetLevels = levels.length >= barCount
        ? levels.slice(0, barCount)
        : [...levels, ...new Array(barCount - levels.length).fill(0)]

      for (let i = 0; i < barCount; i++) {
        const target = targetLevels[i] / 255 // Normalize to 0-1
        const current = currentLevelsRef.current[i]
        // Smooth transition
        currentLevelsRef.current[i] = current + (target - current) * 0.3
      }

      // Clear canvas
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      // Draw bars
      for (let i = 0; i < barCount; i++) {
        const level = currentLevelsRef.current[i]
        const height = minHeight + level * (maxHeight - minHeight)
        const x = i * (barWidth + barGap)
        const y = (maxHeight - height) / 2

        // Create gradient
        const gradient = ctx.createLinearGradient(x, y, x, y + height)
        gradient.addColorStop(0, `${color}`)
        gradient.addColorStop(0.5, `${color}cc`)
        gradient.addColorStop(1, `${color}66`)

        ctx.fillStyle = gradient
        ctx.beginPath()
        ctx.roundRect(x, y, barWidth, height, barWidth / 2)
        ctx.fill()
      }

      animationRef.current = requestAnimationFrame(animate)
    }

    animate()

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current)
      }
    }
  }, [levels, barCount, barWidth, barGap, minHeight, maxHeight, color])

  const totalWidth = barCount * (barWidth + barGap) - barGap

  return (
    <canvas
      ref={canvasRef}
      width={totalWidth}
      height={maxHeight}
      className="block"
      style={{ width: totalWidth, height: maxHeight }}
    />
  )
}
