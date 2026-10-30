const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const names = ['1-home','2-recording','3-overview','4-transcript','5-name-speaker','6-meeting-actions','7-actions-tab','8-processing'];
  for (const theme of ['light','dark']) {
    const p = await b.newPage({ viewport: { width: 3600, height: 940 }, deviceScaleFactor: 2 });
    await p.goto('file://' + process.cwd() + '/screens.html#' + theme);
    await p.waitForTimeout(400);
    for (let i = 0; i < 8; i++) await p.locator('#s' + (i+1)).screenshot({ path: `${theme}/${names[i]}.png` });
    await p.locator('#root').screenshot({ path: `${theme}-all.png` });
    await p.close();
  }
  await b.close();
})();
