const bankColors = {
  green: '#00A550',
  'light-green': '#00C261',
  'dark-green': '#008542',
  red: '#EF4444',
  'dark-red': '#DC2626',
  gold: '#D4AF37',
  'light-gold': '#E6C446',
  blue: '#4682B4',
  orange: '#FFA500',
  bg: '#121212',
  card: '#1E1E1E',
  'card-hover': '#252525',
  text: '#E0E0E0',
  'text-secondary': '#A0A0A0',
  border: '#333333',
  hover: '#2A2A2A',
  frame: '#050506',
};

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/**/*.{html,js,svelte,ts}',
  ],
  theme: {
    extend: {
      colors: {
        bank: bankColors,
        fleeca: bankColors,
      },
      fontFamily: {
        sans: ["Inter", "sans-serif"],
        display: ["Poppins", "sans-serif"],
      },
      boxShadow: {
        card: "0 4px 12px rgba(0, 0, 0, 0.2)",
        hover: "0 6px 16px rgba(0, 0, 0, 0.3)",
        glow: "0 0 15px rgba(0, 165, 80, 0.3)",
      },
    },
  },
  plugins: [],
};
