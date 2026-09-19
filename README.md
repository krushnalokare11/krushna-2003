# Academic portfolio — setup guide

## 1. The files

```
portfolio/
├── index.html      all the content and section structure
├── style.css       all the styling
├── script.js       mobile menu, nav highlighting, publication filter
├── README.md       this file
└── assets/
    ├── profile.jpg              ← your photo (add this)
    ├── cv.pdf                   ← your CV (add this)
    ├── favicon.svg              already here
    ├── profile-placeholder.svg  already here
    └── project-1.jpg …          optional project images
```

Keep this folder structure exactly. The HTML looks for `style.css`, `script.js`
and `assets/` as siblings.

## 2. Your profile photo

Save it as `assets/profile.jpg`.

- Square crop, around 800 × 800 pixels
- Under 300 KB — resize before uploading, a 6 MB phone photo makes the page slow
- Plain background, head and shoulders, looking at the camera

Until you add it, a grey placeholder shows instead, so the page never looks broken.

## 3. Your CV

Save it as `assets/cv.pdf`. Both the button at the top and the CV band near the
bottom point there, so you only replace the one file when your CV changes.
Update the "Last updated" line in the CV section while you're at it.

## 4. Replacing your information

Open `index.html` in any text editor (VS Code, Notepad++, even Notepad). Every
placeholder is written in square brackets — `[YOUR NAME]`, `[YOUR UNIVERSITY]`,
`[PROJECT TITLE]` — so you can find them all with Ctrl+F for `[YOUR`.

Work through it in this order:

1. **Ctrl+H, replace all** `[YOUR NAME]` with your name. Same for
   `[YOUR UNIVERSITY]` and `[YOUR EMAIL]`.
2. **Links.** Search for `yourname` and replace it in the GitHub and LinkedIn
   URLs. Search for `XXXX` for Google Scholar and `0000-0000-0000-0000` for ORCID.
3. **Research interests.** Each is one `<li class="interest">` block. Delete the
   ones that don't apply, copy a block to add one.
4. **Projects.** Each is one `<article class="project">` block. Copy the whole
   block for each new project. If a project has no image, delete the `<img>` line.
5. **Publications.** Each is one `<li class="pub">` block. The `data-kind`
   attribute controls which filter tab it appears under — use `journal`,
   `preprint`, `conference`, `thesis` or `working`. Delete the three placeholder
   entries once you have real ones, and delete the italic "entries below are
   placeholders" line too.
6. **Education and experience.** Each entry is one `<li class="tl-item">` block.
   Newest at the top.
7. **Skills.** Just edit the `<li>` items in each column. Remove anything you
   can't demonstrate in an interview.
8. **SEO block.** Near the top of `index.html` there's a `<script type="application/ld+json">`
   block and some `<meta>` tags. Fill those in — they control what Google shows.

To change the accent colour, edit `--accent` at the top of `style.css`. That one
line controls every blue element on the page.

**Do not** put your home address, phone number, date of birth or full ID numbers
on the page. A department address and an email are what academics expect.

## 5. Testing it locally

Simplest way: double-click `index.html`. It opens in your browser and everything
works.

If you have Python installed, a local server is slightly more faithful to how it
will behave once deployed:

```bash
cd portfolio
python -m http.server 8000
```

Then open `http://localhost:8000`.

Before you publish, check:

- Resize the browser window narrow — the menu should collapse to a ☰ button
- Click every nav link and every external link
- Open it on your phone
- Tab through the page with the keyboard; you should see a visible focus ring

## 6. Publishing on GitHub Pages

1. Create a free account at [github.com](https://github.com).
2. Click **New repository**. Name it exactly `yourusername.github.io`, using your
   real username. Set it to **Public**. Don't add a README.
3. On the empty repository page, click **uploading an existing file**.
4. Drag in `index.html`, `style.css`, `script.js` and the `assets` folder. Upload
   the *contents* of `portfolio/`, not the folder itself — `index.html` must sit
   at the top level of the repository.
5. Click **Commit changes**.
6. Go to **Settings → Pages**. Under "Build and deployment", set Source to
   *Deploy from a branch*, branch `main`, folder `/ (root)`. Save.
7. Wait two or three minutes. Your site is live at
   `https://yourusername.github.io`.

To update anything later, edit the file on GitHub directly (click the file, then
the pencil icon) or upload a new version. Changes appear in about a minute.

**Netlify** is the drag-and-drop alternative: sign in, go to
[app.netlify.com/drop](https://app.netlify.com/drop), drag the folder onto the
page, and you get a link immediately. **Vercel** works the same way. Both accept
this project with no configuration, because there's nothing to build.

### Getting your own domain

Once it's live you can point a custom domain at it — something like
`yourname.com`, around ₹800 a year from a registrar. In your repository, add a
file named `CNAME` containing just your domain, then set the DNS records your
registrar shows you. GitHub's Pages settings walk you through it.

## Notes

- Nothing here needs a build step, npm, or a framework. It's three files a
  browser reads directly, which is why it loads fast and will still work in ten
  years.
- The page prints cleanly — Ctrl+P gives a readable document with the navigation
  stripped out, useful if a committee asks for a PDF.
- Don't add achievements you don't have. Admissions committees check, and a
  short honest page reads better than a padded one.
