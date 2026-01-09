/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        display: ["var(--font-orbitron)", "ui-sans-serif", "system-ui"],
        body: ["var(--font-space)", "ui-sans-serif", "system-ui"],
      },
      colors: {
        void: {
          950: "#05070b",
          900: "#0b1018",
          800: "#121825",
          700: "#1b2333",
          600: "#2b364d"
        },
        neon: {
          400: "#5ff7ff",
          500: "#00e1ff",
          600: "#00b7d4"
        },
        pulse: {
          500: "#ff8bd8",
          600: "#ff54c7"
        }
      },
      boxShadow: {
        glow: "0 0 30px rgba(0, 225, 255, 0.2)",
        pulse: "0 0 35px rgba(255, 84, 199, 0.25)",
      }
    }
  },
  plugins: []
};
