from AjapopajaPlugin import FormatUtil


class TestFormatUtil:
    def test_build_prompt_with_only_prompt(self):
        """Test building prompt with only main prompt text."""
        prompt = "Hello world"
        result = FormatUtil.build_prompt(prompt, "", "")
        assert result == "Hello world"

    def test_build_prompt_with_prompt_and_code(self):
        """Test building prompt with main prompt and code block."""
        prompt = "Write a function"
        lang = "python"
        selected_code = "def hello():\n    return 'world'"
        expected = (
            "Write a function\n\n```python\ndef hello():\n    return 'world'\n```"
        )
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected

    def test_build_prompt_with_empty_prompt_and_code(self):
        """Test building prompt with empty prompt but with code."""
        prompt = ""
        lang = "javascript"
        selected_code = "console.log('hello')"
        expected = "\n\n```javascript\nconsole.log('hello')\n```"
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected

    def test_build_prompt_with_empty_prompt_and_empty_code(self):
        """Test building prompt with empty prompt and empty code."""
        prompt = ""
        lang = ""
        selected_code = ""
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == ""

    def test_build_prompt_with_empty_code(self):
        """Test building prompt with prompt but empty code."""
        prompt = "Hello world"
        lang = ""
        selected_code = ""
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == "Hello world"

    def test_build_prompt_with_code_without_language(self):
        """Test building prompt with code but no language specified."""
        prompt = "Change this:"
        lang = ""
        selected_code = "print('hello')"
        expected = "Change this:\n\n```\nprint('hello')\n```"
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected

    def test_build_prompt_with_code_and_whitespace(self):
        """Test building prompt with code that has leading whitespace."""
        prompt = "Function:"
        lang = "python"
        selected_code = "    def test():\n        return True"
        expected = "Function:\n\n```python\ndef test():\n    return True\n```"
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected

    def test_strip_code_fence_strip_non_fenced_content(self):
        """Test stripping basic code fence."""
        text = "Some text\n```python\nprint('hello')\n```\nMore text"
        expected = "print('hello')"
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_multiple_blocks(self):
        """Test stripping multiple code blocks."""
        text = "Start\n```python\nprint('hello')\n```\nMiddle\n```javascript\nconsole.log('hi')\n```\nEnd"
        expected = "print('hello')\nconsole.log('hi')"
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_no_fences(self):
        """Test stripping code fence from text with no fences."""
        text = "No code blocks here"
        expected = "No code blocks here"
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_empty_text(self):
        """Test stripping code fence from empty text."""
        text = ""
        expected = ""
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_only_fences(self):
        """Test stripping code fence from text with only fences."""
        text = "```\n```"
        expected = ""
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_nested_fences(self):
        """Test stripping code fence with nested fences."""
        text = "Text\n```\n```python\nprint('hello')\n```\n```"
        expected = "print('hello')"
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_strip_code_fence_mixed_content(self):
        """Test stripping code fence with mixed content."""
        text = "Before\n```javascript\nconsole.log('test');\n```\nAfter\n```python\nprint('hello')\n```"
        expected = "console.log('test');\nprint('hello')"
        result = FormatUtil.strip_code_fence(text)
        assert result == expected

    def test_build_prompt_with_dedented_code(self):
        """Test that code is properly dedented."""
        prompt = "Function:"
        lang = "python"
        selected_code = """
            def test():
                return True
        """
        expected = "Function:\n\n```python\n\ndef test():\n    return True\n\n```"
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected

    def test_build_prompt_with_special_characters(self):
        """Test building prompt with special characters in code."""
        prompt = "Code with special chars:"
        lang = "python"
        selected_code = "def func(a, b):\n    return a + b  # comment"
        expected = "Code with special chars:\n\n```python\ndef func(a, b):\n    return a + b  # comment\n```"
        result = FormatUtil.build_prompt(prompt, lang, selected_code)
        assert result == expected
