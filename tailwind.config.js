/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/templates/**/*.html",
    "./app/main.py",
  ],
  safelist: [
    'bg-emerald-100', 'text-emerald-700',
    'bg-slate-100', 'text-slate-500',
    'bg-amber-50', 'border-l-4', 'border-amber-400',
    'bg-amber-200', 'text-amber-800',
    'bg-indigo-100', 'text-indigo-700',
    'bg-green-50/50', 'bg-green-100', 'text-green-700',
    'text-amber-500', 'hover:text-amber-700',
    'animate-spin', 'animate-pulse'
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
