import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";

const MAX_SKILL_FILES = 24;
const MAX_SKILL_BYTES = 256 * 1024;
const ALLOWED_EXTENSIONS = new Set([".md", ".txt", ".json"]);

function parseScalar(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

export function parseSkillFrontmatter(content) {
  const match = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)/);
  if (!match) {
    return {};
  }

  const metadata = {};
  let parentKey;
  for (const line of match[1].split(/\r?\n/)) {
    const topLevelProperty = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (topLevelProperty) {
      const [, key, value] = topLevelProperty;
      parentKey = value ? undefined : key;
      if (value) {
        metadata[key] = parseScalar(value);
      }
      continue;
    }

    const nestedProperty = line.match(/^\s+([A-Za-z0-9_-]+):\s*(.*)$/);
    if (parentKey && nestedProperty) {
      metadata[`${parentKey}.${nestedProperty[1]}`] = parseScalar(nestedProperty[2]);
    }
  }
  return metadata;
}

function isWithinDirectory(parentDirectory, candidatePath) {
  const relative = path.relative(parentDirectory, candidatePath);
  return relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative);
}

function findRelativeLinks(content) {
  const links = [];
  const markdownLink = /\[[^\]]*]\(([^)]+)\)/g;
  for (const match of content.matchAll(markdownLink)) {
    let target = match[1].trim();
    if (target.startsWith("<") && target.endsWith(">")) {
      target = target.slice(1, -1);
    }
    target = target.split(/\s+["']/)[0].split("#")[0];
    if (!target || target.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(target)) {
      continue;
    }
    try {
      links.push(decodeURIComponent(target));
    } catch {
      links.push(target);
    }
  }
  return links;
}

async function readBoundedFile(filePath) {
  const fileInfo = await stat(filePath);
  if (!fileInfo.isFile()) {
    throw new Error(`Skill reference is not a file: ${filePath}`);
  }
  if (fileInfo.size > MAX_SKILL_BYTES) {
    throw new Error(`Skill file is too large: ${filePath}`);
  }
  return { content: await readFile(filePath, "utf8"), fileInfo };
}

export async function loadSkillBundle(skillDirectory) {
  const resolvedSkillDirectory = path.resolve(skillDirectory);
  const skillPath = path.join(resolvedSkillDirectory, "SKILL.md");
  const rootFile = await readBoundedFile(skillPath);
  const files = new Map([[skillPath, rootFile]]);
  const queue = [skillPath];
  let totalBytes = rootFile.fileInfo.size;

  while (queue.length > 0) {
    const currentPath = queue.shift();
    const currentFile = files.get(currentPath);

    for (const relativeLink of findRelativeLinks(currentFile.content)) {
      const candidatePath = path.resolve(path.dirname(currentPath), relativeLink);
      if (!isWithinDirectory(resolvedSkillDirectory, candidatePath)) {
        throw new Error(`Skill reference escapes its directory: ${relativeLink}`);
      }
      if (!ALLOWED_EXTENSIONS.has(path.extname(candidatePath).toLowerCase())) {
        continue;
      }
      if (files.has(candidatePath)) {
        continue;
      }
      if (files.size >= MAX_SKILL_FILES) {
        throw new Error(`Skill contains more than ${MAX_SKILL_FILES} linked files.`);
      }

      const linkedFile = await readBoundedFile(candidatePath);
      totalBytes += linkedFile.fileInfo.size;
      if (totalBytes > MAX_SKILL_BYTES) {
        throw new Error(`Skill bundle exceeds ${MAX_SKILL_BYTES} bytes.`);
      }
      files.set(candidatePath, linkedFile);
      queue.push(candidatePath);
    }
  }

  const metadata = parseSkillFrontmatter(rootFile.content);
  if (!metadata.name) {
    throw new Error(`Skill frontmatter is missing "name": ${skillPath}`);
  }

  const supportingFiles = [...files.entries()]
    .filter(([filePath]) => filePath !== skillPath)
    .sort(([left], [right]) => left.localeCompare(right));
  const supportingContext = supportingFiles
    .map(([filePath, file]) => {
      const relativePath = path.relative(resolvedSkillDirectory, filePath).replaceAll("\\", "/");
      return `--- ${relativePath} ---\n${file.content.trim()}`;
    })
    .join("\n\n");

  const hash = createHash("sha256");
  for (const [filePath, file] of [...files.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    hash.update(path.relative(resolvedSkillDirectory, filePath));
    hash.update("\0");
    hash.update(file.content);
    hash.update("\0");
  }

  return Object.freeze({
    name: metadata.name,
    description: metadata.description || "",
    version: metadata.version || metadata["metadata.version"] || "",
    directory: resolvedSkillDirectory,
    skillPath,
    supportingContext,
    fileCount: files.size,
    hash: hash.digest("hex"),
    modifiedAt: new Date(
      Math.max(...[...files.values()].map(({ fileInfo }) => fileInfo.mtimeMs)),
    ).toISOString(),
  });
}
