(() => {
  const openLink = document.getElementById('open-app');
  const fallback = document.getElementById('open-fallback');
  const status = document.getElementById('open-status');
  const downloadLink = document.getElementById('download-app');
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (isIOS) downloadLink.href = 'https://testflight.apple.com/join/JqADzPK9';
  let autoTimer;
  let fallbackTimer;

  function cancelTimers() {
    clearTimeout(autoTimer);
    clearTimeout(fallbackTimer);
  }

  function prepareAttempt() {
    cancelTimers();
    fallback.hidden = true;
    status.textContent = 'Открываем приложение…';
    fallbackTimer = setTimeout(() => {
      if (document.visibilityState !== 'visible') return;
      fallback.hidden = false;
      status.textContent = '';
      openLink.textContent = 'Попробовать снова';
    }, 2500);
  }

  // оставляем прямую ссылку, чтобы приложение открылось именно по нажатию пользователя
  openLink.addEventListener('click', prepareAttempt);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'hidden') return;
    cancelTimers();
    status.textContent = '';
  });
  window.addEventListener('pagehide', cancelTimers);

  if (document.visibilityState === 'visible') {
    autoTimer = setTimeout(() => {
      if (document.visibilityState !== 'visible') return;
      prepareAttempt();
      window.location.href = openLink.href;
    }, 800);
  }
})();
