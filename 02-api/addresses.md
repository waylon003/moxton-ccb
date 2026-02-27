### 地址自动补全
**GET** `/address/autocomplete`
**认证**: Optional (支持游客和用户)
**说明**: 提供智能地址补全功能，支持中英文地址自动完成，返回结构化地址信息
**查询参数**:
- `input` (必需): 用户输入的地址文本，最少 2 个字符，最多 200 个字符
- `country` (可选): 国家代码，默认为 'au' (澳大利亚)
- `language` (可选): 语言代码，默认为 'en' (英文)
**支持的国家和地区**:
- `au` - 澳大利亚 (en) **默认国家**
- `cn` - 中国 (zh-CN, en)
- `us` - 美国 (en)
- `uk` - 英国 (en)
- `jp` - 日本 (ja, en)
- `kr` - 韩国 (ko, en)
- `sg` - 新加坡 (en, zh-CN)
- `ca` - 加拿大 (en)
- `de` - 德国 (en)
- `fr` - 法国 (en)
- 以及其他主要国家
**示例请求**:
```
# 默认配置（澳大利亚，英文）
GET /address/autocomplete?input=Sydney Opera House
# 指定国家和语言
GET /address/autocomplete?input=北京朝阳区建国门&country=cn&language=zh-CN
GET /address/autocomplete?input=123 Main St&country=us&language=en
GET /address/autocomplete?input=東京新宿&country=jp&language=ja
GET /address/autocomplete?input=Melbourne Cricket Ground&country=au&language=en
```
**响应格式**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "suggestions": [
      {
        "placeId": "ChIJ3c5SiJN2EmsRBfyfZgdnSyI",
        "description": "Sydney Opera House, Bennelong Point, Sydney NSW, Australia",
        "structuredAddress": {
          "addressLine1": "Bennelong Point",
          "addressLine2": "Sydney Opera House",
          "city": "Sydney",
          "state": "NSW",
          "postalCode": "2000",
          "country": "Australia",
          "countryCode": "AU",
          "fullAddress": "Bennelong Point, Sydney Opera House, Sydney NSW 2000, Australia",
          "district": ""
        }
      },
      {
        "placeId": "ChIJ9WGkO8K2EmsRDRpwq3o_2AI",
        "description": "Sydney Harbour Bridge, Sydney NSW, Australia",
        "structuredAddress": {
          "addressLine1": "Sydney Harbour Bridge",
          "addressLine2": "",
          "city": "Sydney",
          "state": "NSW",
          "postalCode": "2000",
          "country": "Australia",
          "countryCode": "AU",
          "fullAddress": "Sydney Harbour Bridge, Sydney NSW 2000, Australia",
          "district": ""
        }
      }
    ],
    "query": {
      "input": "Sydney Opera",
      "country": "au",
      "language": "en"
    },
    "meta": {
      "cacheHit": false,
      "responseTime": 245,
      "resultCount": 2
    }
  },
  "timestamp": "2025-12-17T10:30:00.000Z",
  "success": true
}
```
### **前端集成说明**
**🎯 推荐使用结构化字段**
```javascript
// 用户选择地址建议后，自动填充表单
function selectAddress(suggestion) {
  const address = suggestion.structuredAddress;
  // 自动填充到对应的表单字段
  document.getElementById('addressLine1').value = address.addressLine1;
  document.getElementById('addressLine2').value = address.addressLine2 || '';
  document.getElementById('city').value = address.city;
  document.getElementById('state').value = address.state;
  document.getElementById('postalCode').value = address.postalCode;
  document.getElementById('country').value = address.countryCode;
  // fullAddress 可用于显示或日志
  console.log('完整地址:', address.fullAddress);
}
```
**🏗 建议的表单结构**
```html
<form id="address-form">
  <input type="text" id="addressLine1" placeholder="街道地址" required>
  <input type="text" id="addressLine2" placeholder="公寓/单元号（可选）））">
  <input type="text" id="city" placeholder="城市" required>
  <input type="text" id="state" placeholder=" required>
  <input type="text" id="postalCode" placeholder="邮政编码" required>
  <select id="country" required>
    <option value="AU">澳大利亚</option>
    <option value="CN">中国</option>
    <option value="US">美国</option>
    <!-- 其他国家选项 -->
  </select>
</form>
```
**📦 提交订单**
```javascript
// 收集表单数据
const addressData = {
  addressLine1: document.getElementById('addressLine1').value,
  addressLine2: document.getElementById('addressLine2').value,
  city: document.getElementById('city').value,
  state: document.getElementById('state').value,
  postalCode: document.getElementById('postalCode').value,
  country: document.getElementById('country').options[document.getElementById('country').selectedIndex].text,
  countryCode: document.getElementById('country').value
};
// 提交到订单创建API
POST /api/orders/create
{
  "shippingAddress": addressData,
  "items": [...],
  // 其他订单数据
}
```
**错误响应**:
```json
{
  "code": 400,
  "message": "Validation failed",
  "data": ["Input must be at least 2 characters long"],
  "timestamp": "2025-12-16T10:00:00.000Z",
  "success": false
}
{
  "code": 500,
  "message": "Service unavailable",
  "data": ["Google Maps service is not configured"],
  "timestamp": "2025-12-16T10:00:00.000Z",
  "success": false
}
```
### 地址服务健康检查
**GET** `/address/health`
**认证**: None (公开接口)
**说明**: 检查地址补全服务状态，包括Redis连接和Google Maps API配置
**响应**:
```json
{
  "code": 200,
  "message": "Address service health check",
  "data": {
    "status": "healthy",
    "services": {
      "redis": "connected",
      "googleMaps": "configured"
    },
    "timestamp": "2025-12-08T03:14:25.000Z"
  },
  "success": true
}
```
### 清空地址缓存 (管理员）
**POST** `/address/cache/clear`
**认证**: Required (Admin)
**Header**: `Authorization: Bearer <token>`
**说明**: 清空所有地址补全缓存数据
**响应**:
```json
{
  "code": 200,
  "message": "Address cache cleared successfully",
  "data": {
    "message": "Address cache cleared successfully",
    "timestamp": "2025-12-08T03:14:25.000Z"
  },
  "success": true
}
```
### 获取缓存统计 (管理员）
**GET** `/address/cache/stats`
**认证**: Required (Admin)
**Header**: `Authorization: Bearer <token>`
**说明**: 获取地址缓存使用统计信息
**响应**:
```json
{
  "code": 200,
  "message": "Address cache statistics retrieved successfully",
  "data": {
    "stats": {
      "totalKeys": 1250,
      "memoryUsage": "45.2M"
    },
    "redisConnected": true,
    "timestamp": "2025-12-08T03:14:25.000Z"
  },
  "success": true
}
```
### 📊 地址服务特性
#### 智能缓存机制
- **Redis缓存** - 24小时缓存时间，减少API调用成本
- **缓存命中率** - 目标缓存命中率 80%
- **智能清理** - 自动清理过期缓存数据
- **性能监控** - 实时监控缓存使用情况
#### 全球地址支持
- **多国家支持** - 覆盖全球主要国家和地区
- **本地化语言** - 支持中、英、日、韩等多种语言
- **地址格式化** - 根据不同国家习惯格式化地址
- **结构化数据** - 返回标准化的地址组件
#### 性能优化
- **防抖机制** - 300ms防抖，避免频繁请求
- **结果限制** - 最多返回 5 个建议结果
- **批量处理** - 并行获取多个地址的详细信息
- **速率限制** - 用户级别和IP级别的速率限制
#### 安全与可靠性
- **输入验证** - 严格的输入参数验
- **错误处理** - 完善的错误处理和降级机制
- **API密钥保护** - 服务端调用，不暴露给前端
- **监控日志** - 完整的请求日志和性能监控
### 🌐 前端集成示例
#### JavaScript 地址自动完成组件
```javascript
class AddressAutocomplete {
  constructor(inputElement, options = {}) {
    this.input = inputElement;
    this.options = {
      minLength: 2,
      delay: 300,
      maxSuggestions: 5,
      country: 'au',
      language: 'en',
      ...options
    };
    this.debounceTimer = null;
    this.init();
  }
  init() {
    this.input.addEventListener('input', this.handleInput.bind(this));
    this.createSuggestionsContainer();
  }
  handleInput(event) {
    const value = event.target.value.trim();
    if (value.length < this.options.minLength) {
      this.hideSuggestions();
      return;
    }
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.fetchSuggestions(value);
    }, this.options.delay);
  }
  async fetchSuggestions(input) {
    try {
      const response = await fetch(
        `/address/autocomplete?input=${encodeURIComponent(input)}&country=${this.options.country}&language=${this.options.language}`
      );
      const data = await response.json();
      if (data.success) {
        this.displaySuggestions(data.data.suggestions);
      }
    } catch (error) {
      console.error('获取地址建议失败:', error);
    }
  }
  displaySuggestions(suggestions) {
    const container = this.suggestionsContainer;
    container.innerHTML = '';
    suggestions.forEach(suggestion => {
      const item = document.createElement('div');
      item.className = 'address-suggestion';
      item.textContent = suggestion.description;
      item.addEventListener('click', () => {
        this.selectSuggestion(suggestion);
      });
      container.appendChild(item);
    });
    this.showSuggestions();
  }
  selectSuggestion(suggestion) {
    const address = suggestion.structuredAddress;
    // 填充表单字段
    document.getElementById('addressLine1').value = address.addressLine1;
    document.getElementById('city').value = address.city;
    document.getElementById('state').value = address.state;
    document.getElementById('postalCode').value = address.postalCode;
    document.getElementById('country').value = address.country;
    if (address.district) {
      document.getElementById('district').value = address.district;
    }
    this.hideSuggestions();
    this.input.value = address.fullAddress;
  }
}
// 使用示例 - 默认澳大利亚/英文
const autocomplete = new AddressAutocomplete(
  document.getElementById('address-input')
);
// 或者指定中文
const autocompleteCN = new AddressAutocomplete(
  document.getElementById('address-input-cn'),
  {
    country: 'cn',
    language: 'zh-CN'
  }
);
```
#### CSS 样式
```css
.address-autocomplete-container {
  position: relative;
}
.address-suggestions {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  border: 1px solid #ddd;
  border-top: none;
  background: white;
  max-height: 200px;
  overflow-y: auto;
  z-index: 1000;
}
.address-suggestion {
  padding: 10px;
  cursor: pointer;
  border-bottom: 1px solid #eee;
}
.address-suggestion:hover {
  background: #f5f5f5;
}
.address-suggestion:last-child {
  border-bottom: none;
}
```
### 🔧 订单地址集成
地址补全API可以直接集成到订单创建流程中，提升用户填写地址的体验：
```javascript
// 订单表单中的地址字段集成
const orderForm = {
  // 游客订单创建示例
  async createOrderWithAddress() {
    // 获取地址补全选择的结构化地址
    const address = this.getSelectedAddress();
    const orderData = {
      items: this.getOrderItems(),
      guestInfo: {
        name: document.getElementById('guest-name').value,
        email: document.getElementById('guest-email').value,
        phone: document.getElementById('guest-phone').value
      },
      shippingInfo: {
        consignee: document.getElementById('consignee').value,
        phone: document.getElementById('phone').value,
        address: address.fullAddress
      }
      // 可以同时保存结构化地址到数据库
    };
    const response = await fetch('/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(orderData)
    });
    return response.json();
  }
};
```
### ⚠️ 使用注意事项
1. **API配额管理**: Google Maps API有调用限制，建议监控使用
2. **缓存策略**: 合理使用缓存减少API调用成本
3. **输入验证**: 前端也应进行基本的输入长度和格式验证
4. **错误处理**: 建议在前端实现适当的错误处理和用户提示
5. **国际*: 根据目标用户群体选择合适的默认国家和语言
---
## 🧪 集成测试示例
### 游客完整购物流程
```javascript
// 1. 游客浏览商品
const response = await fetch('http://localhost:3033/products');
const { data: products } = await response.json();
// 2. 查看商品详情
const productResponse = await fetch(`http://localhost:3033/products/${products.list[0].id}`);
const { data: product } = await productResponse.json();
// 3. 创建游客订单
const orderResponse = await fetch('http://localhost:3033/orders', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    items: [
      {
        productId: product.id,
        quantity: 1,
        price: product.price
      }
    ],
    guestInfo: {
      name: '张三',
      email: 'guest@example.com',
      phone: '+1234567890',
      company: 'ABC科技公司'
    },
    shippingInfo: {
      consignee: '李四',
      phone: '+1234567890',
      address: '北京市朝阳区XXX街道XXX
    }
  })
});
const { data: order } = await orderResponse.json();
// 4. 创建支付意图 (Stripe Elements)
const paymentResponse = await fetch('http://localhost:3033/payments/stripe/create-intent', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    orderId: order.id
  })
});
const { data: payment } = await paymentResponse.json();
// 5. 使用Stripe Elements处理支付 (前端集成)
// 需要先安装 @stripe/stripe-js 并初始化Stripe
// import { loadStripe } from '@stripe/stripe-js';
// const stripe = await loadStripe(payment.publishableKey);
// const elements = stripe.elements({ clientSecret: payment.clientSecret });
// 然后创建支付表单并调stripe.confirmPayment()
```
### 用户购物流程
```javascript
// 1. 用户登录
const loginResponse = await fetch('http://localhost:3033/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'user@example.com',
    password: 'password123'
  })
});
const { data: { token } } = await loginResponse.json();
// 2. 使用token访问受保护接
const headers = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${token}`
};
// 3. 创建用户订单
const orderResponse = await fetch('http://localhost:3033/orders', {
  method: 'POST',
  headers,
  body: JSON.stringify({
    items: [
      {
        productId: 'product-id',
        quantity: 1,
        price: '299.99'
      }
    ]
    // 用户订单不需要guestInfo
  })
});
```
---
## 🚀 部署说明
### 环境变量配置
```env
# 数据库配
DATABASE_URL="mysql://username:password@host:port/database"
# JWT配置
JWT_SECRET="your-jwt-secret-key"
# CORS配置
CORS_ORIGINS="http://localhost:3000,https://yourdomain.com"
# Stripe配置
STRIPE_SECRET_KEY="STRIPE_SECRET_KEY_PLACEHOLDER"
STRIPE_PUBLISHABLE_KEY="pk_test_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
# 应用配置
CLIENT_URL="http://localhost:3000"
PORT=3033
NODE_ENV="production"
```
### 健康检查
**GET** `/health`
**认证**: None (公开接口)
**说明**: 检查服务器运行状态，用于负载均衡器健康检查和监控
**响应**:
```json
{
  "code": 200,
  "message": "Server is healthy",
  "data": {
    "status": "ok",
    "timestamp": "2025-12-02T10:00:00.000Z",
    "uptime": 3600,
    "environment": "development"
  },
  "success": true
}
```
### API版本信息
**GET** `/version`
**认证**: None (公开接口)
**说明**: 获取当前API版本信息和环境配置
**响应**:
```json
{
  "code": 200,
  "message": "Version information retrieved successfully",
  "data": {
    "version": "1.0.0",
    "name": "Moxton Lot API",
    "environment": "development",
    "timestamp": "2025-12-02T10:00:00.000Z"
  },
  "success": true
}
```
---
## 📞 技术支持
### API版本控制
- 当前版本: v1.1.2
- 版本策略: URL路径版本控制 (`/api/v1/...`)
- 向后兼容: 保持至少2个大版本的兼容性
### 限流规则
- 一般API: 100请求/分钟
- 支付API: 10请求/分钟
- 认证API: 20请求/分钟
### 联系方式
- **技术支持**: tech-support@moxton.com
- API文档: https://docs.moxton.com/api
- 问题反馈: https://github.com/moxton/lotapi/issues
---
## 📋 版本更新日志
### v1.3.0 (2025-12-08) 🛒
**🆕 新增购物车模式（混合模式）**:
#### 核心功能
- **游客购物车**：无需注册即可使用购物车功能
- **登录用户购物车**：完整的用户购物车管理
- **智能合并**: 用户登录时自动合并游客购物车
- **自动过期**: 购物车30天后自动过期机制
- **数据验证**: 库存检查、价格同步、商品有效性验证
#### 完整API接口
- **基础CRUD**: 获取、添加、更新、删除购物车
- **单项操作**: 单项更新数量、选择状态、删除操
- **统计信息**: 购物车总金额、总数量、选中项统
- **购物车验证**: 检查商品可用性、库存、价格变化
- **购物车合并**: 用户登录时合并游客购物车
#### 数据模型设计
- **Cart**: 支持 userId 和 sessionId 双模式
- **CartItem**: 购物车项管理，支持选择状态
- **级联删除**: 购物车删除时自动删除相关购物车项
- **统计字段**: 自动计算总金额和商品数量
#### 认证策略
- **可选认证**: 使用 `optionalAuthMiddleware` 支持游客和用户
- **智能权限**: 根据token存在情况自动判断用户身份
- **会话管理**: 基于IP+User-Agent+时间戳生成游客会话ID
#### 前端集成支持
- **JavaScript 服务*: 完整的CartService封装
- **React Hook**: useCart自定义Hook示例
- **TypeScript类型**: 完整的类型定义
- **错误处理**: 统一的错误处理和用户提示
#### 技术实现亮
- **混合架构**: 游客和登录用户统一接口设计
- **性能优化**: 数据库索引、缓存策略、单项操作优
- **数据一致性**: 事务处理、库存检查、价格同步
- **安全机制**: 权限验证、输入验证、会话隔离
#### 使用流程
- **游客购物流程**: 浏览→添加→查看→登录合并→下单
- **用户购物流程**: 登录→浏览→添加→管理→下单
- **Mermaid图表**: 完整的时序图和流程说
#### 完整文档
- **API文档**: 所有接口的详细说明和示
- **数据模型**: JSON Schema定义
- **集成指南**: 前端集成最佳实践
- **错误处理**: 常见错误码和处理建议
#### 测试支持
- **API测试示例**: examples/cart-api.http
- **多种场景**: 游客、用户、单项操作、错误场景
- **REST Client**: VS Code REST Client兼容
#### 业务集成
- **订单集成**: 与现有订单模块无缝对
- **支付集成**: 支持混合模式支付流程
- **管理后台**: Soybean Admin购物车管理支
### v1.1.2 (2025-12-04) 🏷
**功能增强**:
#### 层级分类名称显示优化
- **层级名称合并** - 商品API中的分类名称现在自动包含父级分类，如电子产品/手机配件"
- **智能层级识别** - 一级分类直接显示名称，多级分类显示完整路径
- **全API覆盖** - 所有商品相关API都支持层级分类显示（列表、详情、搜索、热门等
- **前端友好** - 无需额外处理，直接显示category.name即可
#### 技术实现
- **Prisma优化查询** - 使用include同时查询分类和父级分类信
- **性能优化** - 单次查询获取完整层级结构，避免N+1查询问题
- **向后兼容** - 不影响现有数据结构和API格式
#### 用户体验提升
- **信息更完整** - 用户可以直接看到商品的完整分类路径
- **导航更清晰** - 有助于用户理解商品在分类体系中的位置
- **SEO友好** - 更好的分类信息有利于搜索引擎优化
#### 文档完善
- **API文档更新** - 新增层级分类名称说明章节
- **示例代码更新** - 提供清晰的对比示
- **集成指导** - 前端集成建议和最佳实践
#### 分类状态管理优化
- **category.status字段** - 所有商品API返回的category对象现在包含status字段 (0=禁用, 1=启用)
- **自动过滤机制** - 禁用分类下的商品不会出现在商品列表、搜索、热门商品等API
- **级联控制逻辑** - 分类禁用时关联商品自动下架，启用时商品可独立控制上架状态
- **完整信息保留** - 商品详情API仍可访问禁用分类商品，返回完整分类信
#### 修复问题
- 🔧 **修复变量名错误** - 修复ProductController中getProductsByCategory方法的page变量问题
- 🔧 **优化查询性能** - 减少数据库查询次数，提升响应速度
**向后兼容**:
- 完全兼容v1.1.1接口
- 不影响现有前端代
- 新的显示格式为纯增强功能
### v1.1.1 (2025-12-04) 🔄
**API优化**:
#### 分类接口重构
- **移除冗余列表接口** - 删除 `/categories` 列表接口，避免路由冲
- **优化树形接口** - `/categories/tree` 返回所有分类（含禁用），`/categories/tree/active` 返回启用分类
- **移除软删除机* - 删除所有软删除相关API，简化数据管理逻辑
- **统一删除接口** - 保留硬删除功能，`DELETE /categories/:id` `DELETE /categories/batch`
- **状态管理优* - 通过status字段管理启用/禁用，删除操作为永久删除
#### 接口清理与简
- 🗑**软删除API移除** - 删除 `/categories/:id/soft`, `/categories/batch/soft`, `/categories/:id/restore`, `/categories/deleted`
- 🗑**批量删除简* - `DELETE /categories/batch/hard` `DELETE /categories/batch`
- **RESTful设计** - 删除操作语义更加明确和直
#### 级联状态管理优
- **级联状态更* - `PUT /categories/batch/status` 现在支持级联更新子分类状
- **状态一致性保* - 父级分类状态变更会自动同步到所有子分类
- **事务保护** - 使用数据库事务确保级联操作的原子
- **详细反馈** - 返回级联更新的详细信息，包括影响的父分类数量
#### 文档更新
- **API文档重构** - 更新接口说明，移除软删除相关文档
- **最佳实践更* - 提供新的分类管理策略指导
- **安全机制说明** - 明确删除操作和状态管理的区别
### v1.1.0 (2025-12-03) 🆕
**新增功能**:
#### 分类管理优化
- **批量删除分类** - 支持一次删除多个分类，自动检查子分类和关联商
- **批量更新分类状态** - 支持批量启用/禁用分类
- **参数处理优化** - 修复空字符串参数导致200错误
- **分类树形结构** - 完整的层级关系管
- **分类路径查询** - 获取完整的分类层级路
- **商品数量统计** - 分类包含的商品数
#### 商品管理增强
- **富文本内容字段** - 新增`content`字段支持HTML格式商品详情
- **批量删除商品** - 支持一次删除多个商品，自动检查订单关
- **批量库存管理** - 支持批量更新商品库存
- **参数处理优化** - 修复空参数和无效值处
- **相关商品推荐** - 基于分类的相关商品功
#### API安全性提
- **批量操作限制** - 防止性能问题的数量限
- **事务保证** - 批量操作使用数据库事务确保一致性
- **关联检* - 删除前自动检查关联关
- **部分失败处理** - 支持部分成功的批量操作响
#### 文档完善
- **统一API文档** - 完整的接口说明和示例
- **新增功能标注** - 🆕 标识最新功
- **认证说明** - 明确每个接口的认证要
- **错误处理** - 详细的错误响应示
**修复问题**:
- 🔧 修复products接口空参200错误
- 🔧 修复Category Controller参数处理问题
- 🔧 优化Prisma客户端生成问
**向后兼容**:
- 完全兼容v1.0.0接口
- 新增字段均为可选）
- 响应格式保持一致
## 📁 文件上传 API (OSS)
