// Hero video controls for the real ListRunner app recording.
const video = document.getElementById("demoVideo");
const toggle = document.getElementById("demoReplay");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function syncToggle() {
  const isPlaying = !video.paused;
  toggle.textContent = isPlaying ? "Pause demo" : "Play demo";
  toggle.setAttribute("aria-pressed", String(isPlaying));
}

function pauseForReducedMotion() {
  if (reducedMotion.matches) video.pause();
  else video.play().catch(() => {});
  syncToggle();
}

toggle.addEventListener("click", () => {
  if (video.paused) video.play().catch(() => {});
  else video.pause();
  syncToggle();
});

video.addEventListener("play", syncToggle);
video.addEventListener("pause", syncToggle);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) video.pause();
  else if (!reducedMotion.matches) video.play().catch(() => {});
  syncToggle();
});
reducedMotion.addEventListener?.("change", pauseForReducedMotion);

pauseForReducedMotion();
