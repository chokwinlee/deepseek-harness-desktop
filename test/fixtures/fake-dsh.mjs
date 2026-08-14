const mode = process.env.FAKE_DSH_MODE ?? 'ready'

const stop = () => { process.exit(0) }
process.on('SIGTERM', stop)
process.on('SIGINT', stop)

if (mode === 'ready') {
  console.log('booting')
  console.log('dsh web: http://127.0.0.1:43123')
} else if (mode === 'exit') {
  console.error('fixture startup failed')
  setTimeout(() => { process.exit(7) }, 10)
} else if (mode === 'unstable') {
  console.log('dsh web: http://127.0.0.1:43123')
  console.error('fixture crashed after readiness')
  setTimeout(() => { process.exit(9) }, 10)
} else if (mode !== 'silent') {
  console.error(`unknown fixture mode: ${mode}`)
  process.exit(8)
}

setInterval(() => {}, 1_000)
