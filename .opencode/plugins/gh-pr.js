/**
 * gh-pr plugin for OpenCode.ai
 *
 * Auto-registers the skills directory via the config hook (no symlinks needed).
 *
 * Unlike superpowers, this plugin injects no per-session bootstrap context.
 * These skills are always invoked explicitly against a named PR or a working
 * tree the user just changed, so OpenCode's native `skill` tool discovering
 * them is all that is needed. Every one of the eight writes something to a live
 * repo, which is a further reason not to keep them in the preamble.
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const GhPrPlugin = async () => {
  const ghPrSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    // Inject skills path into live config so OpenCode discovers gh-pr skills
    // without requiring manual symlinks or config file edits.
    // This works because Config.get() returns a cached singleton — modifications
    // here are visible when skills are lazily discovered later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(ghPrSkillsDir)) {
        config.skills.paths.push(ghPrSkillsDir);
      }
    },
  };
};
