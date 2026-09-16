/**
 * 字符串工具类
 * 提供字符串处理相关的工具函数
 */
export class StringUtil {
  /**
   * 统计字符串中的中文字数
   * 
   * @param text 需要统计的字符串
   * @returns 返回中文字符的数量
   * 
   * @example
   * ```typescript
   * StringUtil.countChineseCharacters('Hello世界123') // 返回 2
   * StringUtil.countChineseCharacters('你好，世界！') // 返回 4
   * StringUtil.countChineseCharacters('ABC123') // 返回 0
   * StringUtil.countChineseCharacters('') // 返回 0
   * ```
   */
  static countChineseCharacters(text: string): number {
    if (!text) {
      return 0;
    }

    // 中文字符的 Unicode 范围：
    // \u4e00-\u9fa5: 基本汉字
    // \u3400-\u4dbf: 扩展A区汉字
    // \u20000-\u2a6df: 扩展B区汉字
    // \u2a700-\u2b73f: 扩展C区汉字
    // \u2b740-\u2b81f: 扩展D区汉字
    // \u2b820-\u2ceaf: 扩展E区汉字
    // \uf900-\ufaff: 兼容汉字
    // \u3300-\u33ff: 汉字的方块符号
    const chineseRegex = /[\u4e00-\u9fa5\u3400-\u4dbf\uf900-\ufaff\u3300-\u33ff]/g;
    const matches = text.match(chineseRegex);
    
    return matches ? matches.length : 0;
  }

  /**
   * 判断字符串是否包含中文字符
   * 
   * @param text 需要检查的字符串
   * @returns 如果包含中文字符返回 true，否则返回 false
   * 
   * @example
   * ```typescript
   * StringUtil.hasChineseCharacters('Hello世界') // 返回 true
   * StringUtil.hasChineseCharacters('ABC123') // 返回 false
   * ```
   */
  static hasChineseCharacters(text: string): boolean {
    if (!text) {
      return false;
    }
    
    const chineseRegex = /[\u4e00-\u9fa5\u3400-\u4dbf\uf900-\ufaff\u3300-\u33ff]/;
    return chineseRegex.test(text);
  }

  /**
   * 获取字符串的实际显示长度（中文字符计为2，英文字符计为1）
   * 
   * @param text 需要计算长度的字符串
   * @returns 返回字符串的显示长度
   * 
   * @example
   * ```typescript
   * StringUtil.getDisplayLength('Hello世界') // 返回 9 (5 + 2*2)
   * StringUtil.getDisplayLength('你好') // 返回 4 (2*2)
   * ```
   */
  static getDisplayLength(text: string): number {
    if (!text) {
      return 0;
    }

    let length = 0;
    for (let i = 0; i < text.length; i++) {
      const char = text.charAt(i);
      // 判断是否为中文字符
      if (/[\u4e00-\u9fa5\u3400-\u4dbf\uf900-\ufaff\u3300-\u33ff]/.test(char)) {
        length += 2;
      } else {
        length += 1;
      }
    }
    
    return length;
  }
}
