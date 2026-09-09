import urlUtilsTest from './test/UrlUtils.test';
import connectionProfileTest from './test/ConnectionProfile.test';
import markdownTest from './test/Markdown.test';
import transcriptTest from './test/Transcript.test';

export default function testsuite() {
  urlUtilsTest();
  connectionProfileTest();
  markdownTest();
  transcriptTest();
}
