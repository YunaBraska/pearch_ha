---
layout: default
title: Get PearchHA
description: Install PearchHA from Homebrew or a signed direct macOS download.
---

<header class="page-heading">
  <p class="eyebrow">Get PearchHA</p>
  <h1>Bring Home Assistant to the menu bar.</h1>
  <p>PearchHA supports macOS 13 and later. You also need a reachable Home Assistant instance that you are allowed to access.</p>
</header>

<section id="homebrew" class="install-step">
  <h2>Homebrew</h2>
  <p>Add and trust the tap once, then install the cask.</p>
  <pre><code>brew tap yunabraska/tap
brew trust yunabraska/tap
brew install --cask pearchha</code></pre>
</section>

<section class="install-step">
  <h2>Direct download</h2>
  <p>Download the latest application archive and move <code>PearchHA.app</code> to Applications. Direct releases are Developer ID signed and notarized. After installation, PearchHA can offer signed Sparkle updates.</p>
  <p><a class="button" href="https://github.com/YunaBraska/pearch_ha/releases/latest">Download the latest release</a></p>
</section>

<section class="install-step">
  <h2>Mac App Store</h2>
  <p>Coming soon. The App Store build will use Apple's update channel.</p>
</section>
