/// Domain allow/deny lists for Worthify.
/// Store **root domains** only (lowercase, no trailing dot), e.g. "hm.com".
/// Always match via: domain == root || domain.endsWith('.$root').

/// Tier-1 retailers / luxury stores to *boost*.
const Set<String> kTier1RetailDomainRoots = {
  'nordstrom.com',
  'selfridges.com',
  'net-a-porter.com',
  'mrporter.com',
  'theoutnet.com',
  'harrods.com',
  'harveynichols.com',
  'brownsfashion.com',
  'bergdorfgoodman.com',
  'saksfifthavenue.com',
  'neimanmarcus.com',
  'bloomingdales.com',
  'macys.com',
  'matchesfashion.com',
  'mytheresa.com',
  'shopbop.com',
  'fwrd.com',
  'endclothing.com', // END.
  'reformation.com',
  'ssense.com',
  'farfetch.com',
  'luisaviaroma.com',
  '24s.com',
};

/// Marketplaces / peer-to-peer: allowed but *penalize* and often cap at 1.
const Set<String> kMarketplaceDomainRoots = {
  'amazon.com', 'amazon.co.uk', 'amazon.de', 'amazon.fr', 'amazon.it', 'amazon.es',
  'ebay.com', 'ebay.co.uk',
  'etsy.com',
  'aliexpress.com',
  'alibaba.com',
  'dhgate.com',
  'depop.com',
  'poshmark.com',
  'vestiairecollective.com',
  'therealreal.com',
  'vinted.com', 'vinted.co.uk',
  'stockx.com',
  'goat.com',
  'zalando.com', 'zalando.de', 'zalando.no', 'zalando.co.uk',
  'shopee.com', 'lazada.com', 'rakuten.co.jp',
  'walmart.com', 'target.com', 'flipkart.com', 'noon.com', 'bol.com',
};

/// Trusted mainstream fashion/apparel retail (general allowlist).
const Set<String> kTrustedRetailDomainRoots = {
  // Global fast fashion & mid-market
  'asos.com',
  'zara.com',
  'hm.com',
  'mango.com',
  'uniqlo.com',
  'cos.com',
  'weekday.com',
  'monki.com',
  'bershka.com',
  'pullandbear.com',
  'stradivarius.com',
  'massimodutti.com',
  'primark.com',
  'aritzia.com',
  'urbanoutfitters.com',
  'anthropologie.com',
  'freepeople.com',
  'everlane.com',
  'madewell.com',
  'revolve.com',
  'boozt.com',
  'only.com',        // ONLY (Bestseller)
  'jackjones.com',   // JACK & JONES (Bestseller)
  'na-kd.com',
  'cottonon.com',
  'showpo.com',
  'beginningboutique.com',
  'tobi.com',
  'windsorstore.com',
  'garageclothing.com',
  'lulus.com',

  // Activewear / outdoor
  'nike.com',
  'adidas.com',
  'puma.com',
  'reebok.com',
  'newbalance.com',
  'asics.com',
  'vans.com',
  'converse.com',
  'underarmour.com',
  'lululemon.com',
  'gymshark.com',
  'fabletics.com',
  'aloyoga.com',
  'outdoorvoices.com',
  'patagonia.com',
  'thenorthface.com',
  'columbia.com',
  'on-running.com',
  'salomon.com',
  'merrell.com',
  'teva.com',
  'hoka.com',

  // Footwear / sneaker retail
  'crocs.com',
  'birkenstock.com',
  'drmartens.com',
  'footlocker.com',
  'finishline.com',
  'snipes.com',
  'jdsports.com', 'jdsports.co.uk',
  'champssports.com',

  // Jewelry / accessories retail
  'pandora.net',
  'tiffany.com',
  'cartier.com',
  'rolex.com',
  'tagheuer.com',
  'omegawatches.com',
  'bulgari.com',
  'breitling.com',
  'longines.com',
  'fossil.com',
  'danielwellington.com',
  'mvmt.com',
  'swarovski.com',
  'skagen.com',
  'citizenwatch.com',
  'seikowatches.com',
  'cluse.com',
  'apm.mc',

  // Eyewear retail
  'ray-ban.com',
  'warbyparker.com',
  'zennioptical.com',
  'eyebuydirect.com',
  'oakley.com',
  'persol.com',
  'mauijim.com',
  'glassesusa.com',
  'sunglasshut.com',
  'smartbuyglasses.com',

  // Bags & luggage
  'samsonite.com',
  'tumi.com',
  'awaytravel.com',
  'rimowa.com',
  'kipling.com',
  'longchamp.com',
  'coach.com',
  'michaelkors.com',
  'katespade.com',
  'guess.com',
  'dooney.com',
  'toryburch.com',
  'herschel.com',
  'eastpak.com',
  'jansport.com',

  // Sustainable / indie
  'pactwear.com',
  'tentree.com',
  'girlfriend.com', // Girlfriend Collective
  'organicbasics.com',
  'kotn.com',
  'matethelabel.com',
  'theslowlabel.com',
  'cuyana.com',
  'allbirds.com',

  // Department stores / regionals
  'marksandspencer.com',
  'houseoffraser.co.uk',
  'johnlewis.com',
  'debenhams.com',
  'myer.com.au',
  'davidjones.com',
  'century21stores.com',
  'lordandtaylor.com',
  'boscovs.com',
  'argos.co.uk',
  'boots.com',
  'very.co.uk',
  'next.co.uk', 'next.com',
  'peek-cloppenburg.de',
  'galerieslafayette.com',
  'otto.de',
  'aboutyou.de', 'aboutyou.com',
  'bonprix.de',
};

/// Aggregators / meta-shopping (allowed, but penalize and cap at 1)
const Set<String> kAggregatorDomainRoots = {
  'lyst.com',
  'modesens.com',
  'shopstyle.com',
  // add regionals you care about:
  'lyst.co.uk',
};

/// Completely banned content/non-commerce domains (blogs, media, social, etc.)
const Set<String> kBannedContentDomainRoots = {
  // Social / Community
  'facebook.com','instagram.com','twitter.com','x.com','pinterest.com','tiktok.com',
  'linkedin.com','reddit.com','youtube.com','snapchat.com','threads.net','discord.com',
  'wechat.com','weibo.com','line.me','vk.com',

  // Blogging / CMS
  'blogspot.com','wordpress.com','tumblr.com','medium.com','substack.com','weebly.com',
  'wixsite.com','squarespace.com','ghost.io','notion.site','livejournal.com','typepad.com',

  // Reference / Q&A
  'quora.com','fandom.com','wikipedia.org','wikihow.com','britannica.com',
  'stackexchange.com','stackoverflow.com','ask.com','answers.com',

  // News / Media
  'bbc.com','cnn.com','nytimes.com','washingtonpost.com','forbes.com','bloomberg.com',
  'reuters.com','huffpost.com','usatoday.com','abcnews.go.com','cbsnews.com','npr.org',
  'time.com','theguardian.com','independent.co.uk','theatlantic.com','vox.com',
  'buzzfeed.com','vice.com','msn.com','dailymail.co.uk','mirror.co.uk','nbcnews.com',
  'latimes.com','insider.com',

  // Creative / art sharing
  'soundcloud.com','deviantart.com','dribbble.com','artstation.com','behance.net',
  'vimeo.com','bandcamp.com','mixcloud.com','last.fm','spotify.com','goodreads.com',

  // Editorial fashion (non-shoppable)
  'vogue.com','elle.com','harpersbazaar.com','cosmopolitan.com','glamour.com',
  'refinery29.com','whowhatwear.com','instyle.com','graziamagazine.com','vanityfair.com',
  'marieclaire.com','teenvogue.com','stylecaster.com','popsugar.com','nylon.com',
  'lifestyleasia.com','thezoereport.com','allure.com','coveteur.com','thecut.com',
  'dazeddigital.com','highsnobiety.com','hypebeast.com','complex.com','gq.com',
  'esquire.com','menshealth.com','wmagazine.com','people.com','today.com','observer.com',
  'standard.co.uk','eveningstandard.co.uk','nssmag.com','grazia.fr','grazia.it',

  // Tech / gadget
  'techcrunch.com','wired.com','theverge.com','engadget.com','gsmarena.com','cnet.com',
  'zdnet.com','mashable.com','makeuseof.com','arstechnica.com','androidauthority.com',
  'macrumors.com','9to5mac.com','digitaltrends.com','imore.com','tomsguide.com','pocket-lint.com',

  // Travel
  'tripadvisor.com','expedia.com','lonelyplanet.com','booking.com','airbnb.com',
  'travelandleisure.com','kayak.com','skyscanner.com',

  // Generic aggregators / spammy directories
  'dealmoon.com','pricegrabber.com','shopmania.com','trustpilot.com','reviewcentre.com',
  'mouthshut.com','sitejabber.com','lookbook.nu','stylebistro.com','redbubble.com',
  'society6.com','teepublic.com','zazzle.com','spreadshirt.com','cafepress.com',
  'archive.org',

  // Forums etc.
  '4chan.org','8kun.top','thefashionspot.com','styleforum.net','superfuture.com',

  // Misc
  'patreon.com','onlyfans.com','ko-fi.com','buymeacoffee.com','pixiv.net','tumgir.com',
};

/// Backwards-compat: if other files still import these names, re-export unified versions.
const Set<String> kTrustedDomainRoots = {
  ...kTier1RetailDomainRoots,
  ...kMarketplaceDomainRoots,
  ...kTrustedRetailDomainRoots,
  ...kAggregatorDomainRoots,
};

const Set<String> kBannedDomainRoots = {
  ...kBannedContentDomainRoots,
};
