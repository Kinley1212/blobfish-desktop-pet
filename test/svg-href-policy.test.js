const assert = require('node:assert/strict');
const test = require('node:test');
const { isSafeSvgHref } = require('../src/core/svg-href-policy');

test('SVG href policy allows local fragments and bundled PNG or WebP data only', () => {
  assert.equal(isSafeSvgHref('#body-gradient'), true);
  assert.equal(isSafeSvgHref('data:image/png;base64,iVBORw0KGgo='), true);
  assert.equal(isSafeSvgHref('data:image/webp;base64,UklGRg=='), true);

  assert.equal(isSafeSvgHref('https://example.com/track.png'), false);
  assert.equal(isSafeSvgHref('file:///private/secret.png'), false);
  assert.equal(isSafeSvgHref('data:image/svg+xml;base64,PHN2Zz4='), false);
  assert.equal(isSafeSvgHref('data:text/html;base64,PGgxPkJvb208L2gxPg=='), false);
  assert.equal(isSafeSvgHref('data:image/png;base64,iVBOR w0KGgo='), false);
  assert.equal(isSafeSvgHref('#'), false);
});
