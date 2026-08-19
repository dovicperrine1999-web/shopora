
const cfg=window.SHOPORA_CONFIG||{};
const sb=supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLISHABLE_KEY);
let session=null,currentUser=null,currentProfile=null,categories=[],catalog=[],activeCategory=null,currentProduct=null,shopPage=null,shopCatalog=[],homeMarkup=null;

const MAURITIUS_BANKS=[
 {id:'mcb',name:'MCB',logo:'🏦'},
 {id:'sbm',name:'SBM Bank',logo:'🏦'},
 {id:'absa',name:'Absa Bank Mauritius',logo:'🏦'},
 {id:'afrasiabank',name:'AfrAsia Bank',logo:'🏦'},
 {id:'bankone',name:'Bank One',logo:'🏦'},
 {id:'maubank',name:'MauBank',logo:'🏦'},
 {id:'hsbc',name:'HSBC Mauritius',logo:'🏦'},
 {id:'standardbank',name:'Standard Bank Mauritius',logo:'🏦'}
];
let cart=JSON.parse(localStorage.getItem('shopora_cart')||'[]'),sellerTab='dashboard',sellerOrders=[],sellerProducts=[],shopData=null,addresses=[],isSeller=false;
const $=id=>document.getElementById(id);
if(!homeMarkup && $('app'))homeMarkup=$('app').innerHTML;
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const money=n=>'MUR '+Number(n||0).toLocaleString('en-MU',{maximumFractionDigits:2});
function toast(s){const t=$('toast');if(!t)return;t.textContent=s;t.classList.add('show');clearTimeout(window.__shoporaToastTimer);window.__shoporaToastTimer=setTimeout(()=>t.classList.remove('show'),3600)}
function openModal(id){$(id).classList.add('open')}
let pageMode='customer';
function setPageMode(mode){
 pageMode=mode==='seller'?'seller':'customer';
 let cf=$('customerFooter'),sf=$('sellerFooter'),d=$('footerDescription');
 if(cf)cf.hidden=pageMode!=='customer';
 if(sf)sf.hidden=pageMode!=='seller';
 if(d)d.textContent=pageMode==='seller'?'Manage your Shopora store and customer orders.':'A local marketplace built for customers.';
}
async function openSellerTab(tab){
 if(!currentUser){openAuth('login');return}
 if(!isSeller){
   await openSeller();
   if(!isSeller)return;
 }
 sellerTab=tab||'dashboard';
 setPageMode('seller');
 renderSeller();
 openModal('seller');
}
function closeModal(id){$(id).classList.remove('open');if(id==='seller')setPageMode('customer')}
function closeAll(){document.querySelectorAll('.modal').forEach(x=>x.classList.remove('open'));setPageMode('customer')}
function goHome(){
 setPageMode('customer');closeAll();shopPage=null;shopCatalog=[];activeCategory=null;
 if(homeMarkup && $('app'))$('app').innerHTML=homeMarkup;
 if($('search'))$('search').value='';
 if($('productTitle'))$('productTitle').textContent='Popular products';
 window.scrollTo({top:0,behavior:'smooth'});
 loadCategories().then(()=>loadCatalog()).catch(()=>loadCatalog());
}
function avatar(url,name=''){return url?`<img class="avatar" src="${esc(url)}">`:`<span class="avatar" style="display:inline-flex;align-items:center;justify-content:center">${esc((name||'U')[0].toUpperCase())}</span>`}
async function setAuthUser(u){
 session=u;currentUser=u?.user||u;currentProfile=null;updateNav();
 if(currentUser){
   const {data}=await sb.from('profiles').select('id,full_name,phone,avatar_url').eq('id',currentUser.id).maybeSingle();
   if(data && currentUser?.id===data.id){
     currentProfile=data;
     currentUser.user_metadata={...currentUser.user_metadata,full_name:data.full_name,avatar_url:data.avatar_url};
     updateNav();
   }
   const {data:ownedShop}=await sb.from('shops').select('id,name,slug,active,logo_url,cover_url').eq('owner_id',currentUser.id).maybeSingle();
   isSeller=!!ownedShop;
   if(ownedShop)shopData=ownedShop;
   updateNav();
   loadNotifications();
 }else{
   isSeller=false;
   shopData=null;
 }
}
function updateNav(){
 let name=currentProfile?.full_name||currentUser?.user_metadata?.full_name||currentUser?.email?.split('@')[0]||'Account';
 let pic=currentProfile?.avatar_url||currentUser?.user_metadata?.avatar_url||null;
 $('accountBtn').innerHTML=currentUser?`${avatar(pic,name)}${esc(name)}`:'Account';
}
function cartKey(){return JSON.stringify(cart.map(x=>[x.product_id,x.quantity]))}
function saveCart(){localStorage.setItem('shopora_cart',JSON.stringify(cart));$('cartCount').textContent=cart.reduce((a,x)=>a+x.quantity,0)}
function addCart(p){if(!currentUser){openAuth('login');return}if(p.stock<=0){toast('This product is out of stock');return}let x=cart.find(x=>x.product_id===p.id);if(x)x.quantity=Math.min(x.quantity+1,p.stock);else cart.push({product_id:p.id,shop_id:p.shop_id,name:p.name,price:Number(p.price),quantity:1,image_url:p.image_url,stock:p.stock});saveCart();toast('Added to cart')}
function removeCart(id){cart=cart.filter(x=>x.product_id!==id);saveCart();renderCart()}
function changeQty(id,d){let x=cart.find(x=>x.product_id===id);if(!x)return;x.quantity+=d;if(x.quantity<=0)removeCart(id);else{x.quantity=Math.min(x.quantity,x.stock);saveCart();renderCart()}}
function openCart(){if(!currentUser){openAuth('login');return}renderCart();openModal('cart')}
async function loadCategories(){
 try{
  const {data,error}=await sb.from('categories')
    .select('id,name,slug,image_url,active')
    .eq('active',true)
    .order('name',{ascending:true});
  if(error)throw error;
  categories=data||[];
  const categoryIcons={
   'Electronics':'📱','Phones & Accessories':'📱','Computers':'💻','Gaming':'🎮',
   'Motorcycles & Accessories':'🏍️','Cars & Accessories':'🚗','Fashion - Men':'👔',
   'Fashion - Women':'👗','Shoes':'👟','Beauty & Personal Care':'💄','Home & Living':'🏠',
   'Kitchen':'🍳','Sports & Fitness':'⚽','Baby & Kids':'🧸','Toys':'🧸',
   'Food & Grocery':'🛒','Books & Stationery':'📚','Tools & Hardware':'🔧',
   'Services':'🛠️','Other':'🛍️'
  };
  $('categories').innerHTML=categories.length
   ? categories.map(c=>`<button class="cat" onclick="chooseCategory('${esc(c.id)}','${esc(c.name)}')"><span class="catIcon">${categoryIcons[c.name]||'🛍️'}</span><span>${esc(c.name)}</span></button>`).join('')
   : '<div class="empty">No categories have been created yet.</div>';
 }catch(e){
  console.error('loadCategories:',e);
  categories=[];
  $('categories').innerHTML='<div class="empty">Categories could not be loaded. Please refresh.</div>';
  toast(e?.message||'Could not load categories');
 }
}
function chooseCategory(id,name){
 // This is the global marketplace category selector, not a shop category.
 shopPage=null;
 activeCategory=id;
 $('productTitle').textContent=name;
 loadCatalog();
}

function openSellerStore(id){
 if(!id){toast('Store unavailable');return}
 openShopById(id);
}
async function openShopById(id){
 try{
   const {data,error}=await sb.rpc('get_shopora_shop',{p_shop:id});
   if(error)throw error;
   const shop=data?.shop;
   if(!shop){toast('This store is unavailable');return}
   await openShopPage(shop);
 }catch(e){toast(e?.message||'Could not open store')}
}
function shopCategoryIcon(name){
 const n=String(name||'').toLowerCase();
 const icons=[
  ['electronics','📱'],['phones','📱'],['computer','💻'],['gaming','🎮'],
  ['motorcycle','🏍️'],['car','🚗'],['fashion - men','👔'],['fashion - women','👗'],
  ['shoe','👟'],['beauty','💄'],['home','🏠'],['kitchen','🍳'],['sport','⚽'],
  ['baby','🧸'],['toy','🧸'],['food','🛒'],['grocery','🛒'],['book','📚'],
  ['stationery','📚'],['tool','🔧'],['service','🛠️']
 ];
 const hit=icons.find(([k])=>n.includes(k)); return hit?hit[1]:'📦';
}
function renderShopProducts(items){
 const el=$('shopProducts'); if(!el)return;
 if(!items.length){el.innerHTML='<div class="empty">No products found in this shop.</div>';return}
 el.innerHTML=items.map(p=>`<article class="card">
  <div class="cardimg"><img src="${esc(p.image_url||'')}" alt="${esc(p.name)}" onerror="this.style.display='none'">${p.image_count>1?`<span class="photo-count">▣ ${p.image_count}</span>`:''}</div>
  <div class="cardbody"><h3>${esc(p.name)}</h3><div class="desc">${esc(p.description||'')}</div>
  <div class="price">${money(p.price)} ${p.compare_price?`<span class="old">${money(p.compare_price)}</span>`:''}</div>
  <div class="shopline">Stock: ${Number(p.stock||0)} · ⭐ ${Number(p.rating||0).toFixed(1)}</div>
  <div class="cardactions"><button class="btn" onclick="viewProduct('${p.id}')">View</button><button class="btn primary" onclick='addCart(${JSON.stringify(p).replace(/'/g,"&#39;")})'>Add to cart</button></div></div>
 </article>`).join('');
}
function renderShopPageCategories(){
 const el=$('shopCategories'); if(!el)return;
 // STORE PAGE: show ONLY categories for which this store currently has
 // available/catalogued products. The home page uses loadCategories() and
 // therefore continues to show every marketplace category.
 const seen=new Map();
 shopCatalog.forEach(p=>{
   if(p.category_id && p.category_name && Number(p.stock||0)>0)
     seen.set(p.category_id,p.category_name);
 });
 const cats=[...seen.entries()];
 el.innerHTML=cats.length
   ? cats.map(([id,name])=>`<button class="cat shopcat" onclick="filterShopCategory('${id}',this)">
       <span class="caticon">${shopCategoryIcon(name)}</span><b>${esc(name)}</b>
     </button>`).join('')
   : '<div class="empty">This store has no available categories yet.</div>';
}
function filterShopCategory(id,btn){
 document.querySelectorAll('.shopcat').forEach(x=>x.classList.remove('active'));
 if(btn)btn.classList.add('active');
 const q=($('shopSearch')?.value||'').trim().toLowerCase();
 let items=shopCatalog.filter(p=>p.category_id===id);
 if(q)items=items.filter(p=>String(p.name||'').toLowerCase().includes(q)||String(p.description||'').toLowerCase().includes(q)||String(p.brand||'').toLowerCase().includes(q));
 $('shopProductTitle').textContent=`${items.length} product${items.length===1?'':'s'} in ${document.querySelector('.shopcat.active b')?.textContent||'category'}`;
 renderShopProducts(items);
}
function searchInsideShop(){
 const q=($('shopSearch')?.value||'').trim().toLowerCase();
 document.querySelectorAll('.shopcat').forEach(x=>x.classList.remove('active'));
 let items=shopCatalog;
 if(q)items=items.filter(p=>String(p.name||'').toLowerCase().includes(q)||String(p.description||'').toLowerCase().includes(q)||String(p.brand||'').toLowerCase().includes(q));
 $('shopProductTitle').textContent=q?`Search results for "${esc(q)}"`:`All products in ${esc(shopPage?.name||'this shop')}`;
 renderShopProducts(items);
}
async function openShopPage(shop){
 shopPage=shop;activeCategory=null;
 let shopObject=shop;
 try{
   const r=await sb.rpc('get_shopora_shop',{p_shop:shopObject.id});
   if(!r.error && r.data?.shop){shopObject=r.data.shop;shopCatalog=r.data.products||[]}
   else{
     const r2=await sb.rpc('get_shopora_catalog',{p_search:'',p_category:null,p_shop:shopObject.id,p_sort:'newest',p_min:null,p_max:null,p_limit:100,p_offset:0});
     if(r2.error)throw r2.error;
     shopCatalog=r2.data||[];
   }
 }catch(e){toast(e?.message||'Could not load store');return}
 shopPage=shopObject;
 $('app').innerHTML=`<section class="shop-page">
  <button class="btn shop-back" onclick="goHome()">← Back to Shopora</button>
  <div class="shop-hero">
   <div class="shop-cover">${shopObject.cover_url?`<img src="${esc(shopObject.cover_url)}" alt="${esc(shopObject.name)}">`:''}</div>
   <div class="shop-head">
    <div class="shop-logo">${shopObject.logo_url?`<img src="${esc(shopObject.logo_url)}" alt="${esc(shopObject.name)}">`:`<span>${esc((shopObject.name||'S')[0].toUpperCase())}</span>`}</div>
    <div><h1>${esc(shopObject.name)}</h1><p>${esc(shopObject.description||'Local Shopora seller')}</p>${shopObject.address?`<small>📍 ${esc(shopObject.address)}</small>`:''}</div>
   </div>
  </div>
  <div class="shop-search"><input id="shopSearch" placeholder="Search products in ${esc(shopObject.name)}…" onkeydown="if(event.key==='Enter')searchInsideShop()"><button class="btn primary" onclick="searchInsideShop()">Search store</button></div>
  <h2>Categories</h2>
  <div id="shopCategories" class="cats shopcats"></div>
  <div class="sectionhead"><h2 id="shopProductTitle">All products in ${esc(shopObject.name)}</h2><span class="muted">${shopCatalog.length} available</span></div>
  <div id="shopProducts" class="grid"></div>
 </section>`;
 renderShopPageCategories();renderShopProducts(shopCatalog);
 window.scrollTo({top:0,behavior:'smooth'});
}
async function findShopBySearch(q){
 const clean=q.trim(); if(!clean)return null;
 let {data,error}=await sb.from('shops').select('id,name,slug,description,address,phone,logo_url,cover_url').eq('active',true).ilike('name',`%${clean}%`).limit(1);
 if(error)throw error;
 if(data?.[0])return data[0];
 const slug=clean.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'');
 if(!slug)return null;
 ({data,error}=await sb.from('shops').select('id,name,slug,description,address,phone,logo_url,cover_url').eq('active',true).ilike('slug',`%${slug}%`).limit(1));
 if(error)throw error;
 return data?.[0]||null;
}
async function searchCatalog(){
 const input=$('search'),btn=$('searchBtn'),q=input.value.trim();
 activeCategory=null;
 if(btn){btn.disabled=true;btn.textContent='Searching…'}
 try{
   if(q){
     const shop=await findShopBySearch(q);
     if(shop){await openShopPage(shop);return}
   }
   if(homeMarkup && $('app') && !$('products'))$('app').innerHTML=homeMarkup;
   if($('productTitle'))$('productTitle').textContent=q?`Search results for "${esc(q)}"`:'All products';
   await loadCatalog(q);
   document.getElementById('products')?.scrollIntoView({behavior:'smooth',block:'start'});
 }catch(e){
   if($('products'))$('products').innerHTML=`<div class="empty">Search failed.<br>${esc(e?.message||'Please try again.')}</div>`;
   toast(e?.message||'Search failed');
 }finally{
   if(btn){btn.disabled=false;btn.textContent='Search'}
 }
}
async function loadCatalog(searchOverride=null){
 const root=$('products');
 if(!root)return;
 const q=searchOverride===null?($('search')?.value||'').trim():String(searchOverride).trim();
 const min=$('minPrice')?.value||null;
 const max=$('maxPrice')?.value||null;
 const sort=$('sort')?.value||'newest';
 root.innerHTML='<div class="empty">Loading products…</div>';

 try{
  const {data,error}=await sb.rpc('get_shopora_catalog',{
   p_search:q,p_category:activeCategory,p_shop:null,p_sort:sort,
   p_min:min,p_max:max,p_limit:80,p_offset:0
  });
  if(!error){
   catalog=data||[];
   renderCatalog();
   return;
  }
  console.warn('get_shopora_catalog failed; using direct catalog fallback:',error);
 }catch(e){
  console.warn('Catalog RPC failed; using direct catalog fallback:',e);
 }

 try{
  let query=sb.from('products')
   .select('id,name,description,price,compare_price,stock,rating,review_count,sales_count,shop_id,category_id,created_at,status,shops!inner(id,name,slug,active),categories(id,name)')
   .eq('status','active').gt('stock',0).eq('shops.active',true);

  if(activeCategory)query=query.eq('category_id',activeCategory);
  if(min)query=query.gte('price',Number(min));
  if(max)query=query.lte('price',Number(max));
  if(q){
   const safe=q.replace(/[%_]/g,'\\$&');
   query=query.or(`name.ilike.%${safe}%,description.ilike.%${safe}%`);
  }

  if(sort==='price_asc')query=query.order('price',{ascending:true});
  else if(sort==='price_desc')query=query.order('price',{ascending:false});
  else if(sort==='popular')query=query.order('sales_count',{ascending:false});
  else if(sort==='rating')query=query.order('rating',{ascending:false});
  else query=query.order('created_at',{ascending:false});

  const {data,error}=await query.limit(80);
  if(error)throw error;

  const rows=data||[], ids=rows.map(x=>x.id);
  let images=[];
  if(ids.length){
   const ir=await sb.from('product_images')
    .select('product_id,image_url,sort_order')
    .in('product_id',ids).order('sort_order',{ascending:true});
   if(!ir.error)images=ir.data||[];
  }

  const firstImage=new Map(), imageCount=new Map();
  images.forEach(im=>{
   imageCount.set(im.product_id,(imageCount.get(im.product_id)||0)+1);
   if(!firstImage.has(im.product_id))firstImage.set(im.product_id,im.image_url);
  });

  catalog=rows.map(p=>({
   id:p.id,name:p.name,description:p.description,price:p.price,compare_price:p.compare_price,
   stock:p.stock,rating:p.rating||0,review_count:p.review_count||0,sales_count:p.sales_count||0,
   shop_id:p.shops?.id||p.shop_id,shop_name:p.shops?.name||'',shop_slug:p.shops?.slug||'',
   category_id:p.category_id,category_name:p.categories?.name||'',
   image_url:firstImage.get(p.id)||'',image_count:imageCount.get(p.id)||0
  }));
  renderCatalog();
 }catch(e){
  console.error('loadCatalog fallback:',e);
  catalog=[];
  root.innerHTML=`<div class="empty">Products could not be loaded.<br>${esc(e?.message||'Please refresh and try again.')}</div>`;
  toast(e?.message||'Could not load products');
 }
}
function renderCatalog(){
 if(!catalog.length){$('products').innerHTML='<div class="empty">No products found.</div>';return}
 $('products').innerHTML=catalog.map(p=>`<article class="card">
 <div class="cardimg"><img src="${esc(p.image_url||'')}" onerror="this.style.display='none'"><button class="heart" onclick="toggleWish('${p.id}',event)">♡</button>${p.image_count>1?`<span class="photo-count">▣ ${p.image_count}</span>`:''}</div>
 <div class="cardbody"><h3>${esc(p.name)}</h3><div class="desc">${esc(p.description||'')}</div><div class="price">${money(p.price)} ${p.compare_price?`<span class="old">${money(p.compare_price)}</span>`:''}</div><div class="shopline">Seller: <button type="button" class="linkbtn" onclick="openSellerStore('${p.shop_id}')">${esc(p.shop_name)}</button> · ⭐ ${Number(p.rating||0).toFixed(1)}</div>
 <div class="cardactions"><button class="btn" onclick="viewProduct('${p.id}')">View</button><button class="btn primary" onclick='addCart(${JSON.stringify(p).replace(/'/g,"&#39;")})'>Add to cart</button></div></div></article>`).join('')
}
async function toggleWish(id,e){e.stopPropagation();if(!currentUser){openAuth('login');return}let {data,error}=await sb.rpc('toggle_shopora_wishlist',{p_product:id});if(error)toast(error.message);else toast(data?'Added to wishlist':'Removed from wishlist')}
async function viewProduct(id){
 let {data,error}=await sb.rpc('get_shopora_product',{p_product:id});if(error){toast(error.message);return}currentProduct=data;renderProduct();openModal('productModal')
}
function renderProduct(){
 let p=currentProduct.product,s=currentProduct.shop,imgs=currentProduct.images||[],reviews=currentProduct.reviews||[];
 $('productBody').innerHTML=`<div class="detail"><div class="gallery"><div class="gallerymain"><img id="mainProductImage" src="${esc(imgs[0]?.image_url||'')}"></div><div class="thumbs">${imgs.map((i,n)=>`<img class="${n===0?'active':''}" src="${esc(i.image_url)}" onclick="pickImage('${esc(i.image_url)}',this)">`).join('')}</div></div>
 <div><div class="shopline">${esc(currentProduct.category?.name||'')}</div><h1>${esc(p.name)}</h1><div class="stars">★★★★★ <span style="color:#64748b">${Number(p.rating||0).toFixed(1)} (${p.review_count||0})</span></div><div class="price">${money(p.price)} ${p.compare_price?`<span class="old">${money(p.compare_price)}</span>`:''}</div><p>${esc(p.description)}</p><p><b>${p.stock}</b> in stock</p><p>Sold by <button type="button" class="linkbtn" onclick="closeModal('productModal');openSellerStore('${s.id}')"><b>${esc(s.name)}</b></button></p><div class="cardactions"><button class="btn" onclick="closeModal('productModal')">Close</button><button class="btn" onclick="closeModal('productModal');openSellerStore('${s.id}')">View store</button><button class="btn primary" ${p.stock<=0?'disabled':''} onclick="addCart({...catalog.find(x=>x.id===p.id),image_url:${JSON.stringify(imgs[0]?.image_url||'')}})">Add to cart</button></div><hr><h3>Reviews</h3>${reviews.length?reviews.map(r=>`<div class="order"><b>${esc(r.customer)}</b> <span class="stars">${'★'.repeat(r.rating)}${'☆'.repeat(5-r.rating)}</span><br><b>${esc(r.title)}</b><p>${esc(r.body)}</p></div>`).join(''):'<p class="desc">No reviews yet.</p>'}</div></div>`
}
function pickImage(url,el){$('mainProductImage').src=url;document.querySelectorAll('.thumbs img').forEach(x=>x.classList.remove('active'));el.classList.add('active')}
function renderCart(){
 if(!cart.length){$('cartBody').innerHTML=`<div class="empty">Your cart is empty.<br><button class="btn primary" onclick="closeModal('cart');document.getElementById('products').scrollIntoView()">Continue shopping</button></div>`;return}
 let total=cart.reduce((a,x)=>a+x.price*x.quantity,0);
 $('cartBody').innerHTML=cart.map(x=>`<div class="cartrow"><img src="${esc(x.image_url||'')}"><div><b>${esc(x.name)}</b><div>${money(x.price)} × ${x.quantity}</div><button class="btn small danger" onclick="removeCart('${x.product_id}')">Remove</button></div><div class="qty"><button onclick="changeQty('${x.product_id}',-1)">−</button><span>${x.quantity}</span><button onclick="changeQty('${x.product_id}',1)">+</button></div></div>`).join('')+`<div style="text-align:right;margin-top:18px"><h2>Total ${money(total)}</h2><button class="btn primary" onclick="openCheckout()">Checkout</button></div>`
}
async function openCheckout(){
 if(!currentUser){openAuth('login');return}
 if(!cart.length){toast('Your cart is empty');return}

 /* Open immediately so a slow/broken RPC can never make the Checkout
    button appear dead. */
 openModal('checkout');
 $('checkoutBody').innerHTML='<div class="notice">Preparing secure checkout…</div>';

 const checkoutItems=cart.map(x=>({
   product_id:x.product_id,
   shop_id:x.shop_id,
   quantity:Math.max(1,Number(x.quantity)||1)
 }));

 try{
   const result=await sb.rpc('get_shopora_checkout_payment_options',{p_items:checkoutItems});
   if(result.error) throw result.error;

   await loadAddresses();

   const shops=(result.data||[]).map(s=>({
     ...s,
     methods:(Array.isArray(s.methods)?s.methods:[])
       .filter(m=>m&&m.name&&String(m.name).trim())
   }));

   if(!shops.length){
     $('checkoutBody').innerHTML=`
       <div class="error">
         <b>Checkout could not be prepared.</b>
         <p>The product is no longer available. Please close checkout and refresh the products.</p>
       </div>
       <button class="btn" onclick="closeModal('checkout');loadCatalog()">Close</button>`;
     return;
   }

   const subtotal=shops.reduce((a,s)=>a+Number(s.subtotal||0),0);
   const shipping=shops.reduce((a,s)=>a+Number(s.shipping||0),0);
   const total=subtotal+shipping;

   const paymentHtml=shops.map(s=>{
     const id=`pay_${s.shop_id}`;
     const methods=s.methods;
     return `<div class="order" style="margin-top:10px">
       <b>${esc(s.shop_name)}</b>
       <div class="form" style="margin-top:8px">
         <label>Payment method</label>
         <select id="${id}" ${methods.length?'':'disabled'}>
           ${methods.length
             ?methods.map(m=>`<option value="${esc(m.name)}">${esc(m.name)}</option>`).join('')
             :'<option value="">Seller has not added a payment method</option>'}
         </select>
         <div id="${id}_details" class="notice" style="margin-top:8px"></div>
       </div>
     </div>`;
   }).join('');

   $('checkoutBody').innerHTML=`
     <div class="formgrid">
       <div>
         <h3>Delivery address</h3>
         <div id="addressList"></div>
         <button class="btn" type="button" onclick="addAddressForm()">+ Add address</button>
       </div>
       <div>
         <h3>Payment</h3>
         <div class="notice">Each seller controls their own payment method and payment details.</div>
         ${paymentHtml}
         <div class="form" style="margin-top:12px">
           <label>Payment reference / transaction ID (optional)</label>
           <input id="payRef" placeholder="Reference / transaction ID">
           <label>Payment proof (optional)</label>
           <input id="proof" type="file" accept="image/jpeg,image/png,image/webp,application/pdf">
         </div>
       </div>
     </div>
     <hr>
     <div>
       <h3>Order summary</h3>
       <div style="display:flex;justify-content:space-between"><span>Subtotal</span><b>${money(subtotal)}</b></div>
       <div style="display:flex;justify-content:space-between;margin-top:6px"><span>Shipping</span><b>${shipping?money(shipping):'FREE'}</b></div>
       <div style="display:flex;justify-content:space-between;margin-top:10px;font-size:1.15em"><span>Total</span><b>${money(total)}</b></div>
       <button id="placeOrderBtn" type="button" class="btn primary" style="margin-top:14px;width:100%" onclick="placeOrder()">Place order</button>
     </div>`;

   renderAddressList();

   shops.forEach(s=>{
     const sel=$(`pay_${s.shop_id}`);
     if(sel){
       const render=()=>{
         const m=s.methods.find(x=>String(x.name)===String(sel.value));
         $(`pay_${s.shop_id}_details`).textContent=
           m?.details||'No payment instructions were provided by this seller.';
       };
       sel.addEventListener('change',render);
       render();
     }
   });
 }catch(error){
   console.error('Shopora checkout preparation failed:',error);
   $('checkoutBody').innerHTML=`
     <div class="error">
       <b>Unable to prepare checkout.</b>
       <p>${esc(error?.message||'Please try again.')}</p>
     </div>
     <div style="display:flex;gap:8px">
       <button class="btn primary" type="button" onclick="openCheckout()">Try again</button>
       <button class="btn" type="button" onclick="closeModal('checkout')">Close</button>
     </div>`;
 }
}

async function placeOrder(){
 const btn=$('placeOrderBtn');
 if(btn?.disabled)return;

 const radio=document.querySelector('input[name="addr"]:checked');
 if(!radio){toast('Choose a delivery address');return}
 const addr=addresses.find(x=>x.id===radio.value);
 if(!addr){toast('Address not found');return}

 const selects=[...document.querySelectorAll('select[id^="pay_"]')];
 const paymentMethods={};
 for(const sel of selects){
   const shopId=sel.id.slice(4);
   const method=(sel.value||'').trim();
   if(!method){toast('Select a payment method for every seller');return}
   paymentMethods[shopId]=method;
 }

 const ref=$('payRef')?.value.trim()||'';
 const proofFile=$('proof')?.files?.[0]||null;
 let proof=null;

 if(proofFile){
   if(proofFile.size>10*1024*1024){toast('Payment proof must be 10 MB or smaller');return}
   const allowed=['image/jpeg','image/png','image/webp','application/pdf'];
   if(!allowed.includes(proofFile.type)){toast('Use JPG, PNG, WEBP or PDF for payment proof');return}
 }

 if(btn){btn.disabled=true;btn.textContent='Processing order…'}

 try{
   if(proofFile){
     const safeName=proofFile.name.replace(/[^a-zA-Z0-9._-]/g,'_');
     const path=`${currentUser.id}/${crypto.randomUUID()}-${safeName}`;
     const up=await sb.storage.from('payment-proofs').upload(path,proofFile,{upsert:false});
     if(up.error)throw up.error;
     proof=path;
   }

   const {data,error}=await sb.rpc('create_shopora_order_v52',{
     p_items:cart.map(x=>({product_id:x.product_id,shop_id:x.shop_id,quantity:x.quantity})),
     p_address:addr,
     p_payment_methods:paymentMethods,
     p_payment_reference:ref,
     p_payment_proof:proof,
     p_coupon:null
   });
   if(error)throw error;

   cart=[];saveCart();
   closeModal('checkout');closeModal('cart');
   toast(`Order ${data.order_number} placed successfully`);
   openOrders();
 }catch(error){
   toast(error?.message||'Could not place the order');
 }finally{
   if(btn){btn.disabled=false;btn.textContent='Place order'}
 }
}

async function openOrders(){
 if(!currentUser){openAuth('login');return}
 $('ordersBody').innerHTML='<div class="loading">Loading your orders…</div>';
 openModal('orders');
 try{
   const {data,error}=await sb.rpc('get_shopora_customer_orders',{p_status:null});
   if(error)throw error;
   $('ordersBody').innerHTML=`<div class="tabs"><button class="tab active">All orders</button></div>${(data||[]).map(renderCustomerOrder).join('')||'<div class="empty">No orders yet. Your completed orders will appear here.</div>'}`;
 }catch(e){
   $('ordersBody').innerHTML=`<div class="error"><b>Could not load your orders.</b><br>${esc(e.message||'Please try again.')}</div><button class="btn primary" onclick="openOrders()">Try again</button>`;
 }
}
async function confirmReceived(id){let {error}=await sb.rpc('customer_confirm_shopora_received',{p_seller_order:id});if(error)toast(error.message);else{toast('Receipt confirmed');openOrders()}}
async function openNotifications(){if(!currentUser){openAuth('login');return}let {data,error}=await sb.rpc('get_shopora_notifications',{});if(error){toast(error.message);return}$('notificationsBody').innerHTML=`<button class="btn small" onclick="markAllNotifications()">Mark all read</button><div style="margin-top:10px">${(data||[]).map(n=>`<div class="order" onclick="readNotification('${n.id}')"><b>${esc(n.title)}</b>${n.read_at?'':' <span class="badge">NEW</span>'}<p>${esc(n.message)}</p><small>${new Date(n.created_at).toLocaleString()}</small></div>`).join('')||'<div class="empty">No notifications.</div>'}</div>`;openModal('notifications')}
async function readNotification(id){await sb.rpc('mark_shopora_notification_read',{p_id:id});openNotifications();loadNotifications()}
async function markAllNotifications(){await sb.rpc('mark_all_shopora_notifications_read');openNotifications();loadNotifications()}
async function loadNotifications(){if(!currentUser){$('notifCount').textContent='';return}let {data}=await sb.rpc('get_shopora_notifications',{});let n=(data||[]).filter(x=>!x.read_at).length;$('notifCount').textContent=n?`(${n})`:''}

function openAuth(mode='login'){closeAll();$('authTitle').textContent=mode==='login'?'Log in':'Create account';$('authBody').innerHTML=mode==='login'?loginForm():signupForm();openModal('auth')}
function loginForm(){return `<form class="form" onsubmit="login(event)"><input id="loginEmail" type="email" placeholder="Email address" required><input id="loginPassword" type="password" placeholder="Password" required><button class="btn primary">Log in</button><button type="button" class="btn" onclick="openAuth('signup')">Create account</button><button type="button" class="btn" onclick="resetPassword()">Forgot password?</button><div id="authMsg"></div></form>`}
function signupForm(){return `<form class="form" onsubmit="signup(event)"><input id="signName" placeholder="Full name" required><input id="signPhone" placeholder="Phone number" required><input id="signEmail" type="email" placeholder="Email address" required><input id="signPassword" type="password" minlength="6" placeholder="Password (6+ characters)" required><button class="btn primary">Create account</button><button type="button" class="btn" onclick="openAuth('login')">Already registered? Log in</button><div id="authMsg"></div></form>`}
async function signup(e){e.preventDefault();$('authMsg').innerHTML='<div class="notice">Creating account and sending verification email…</div>';let {data,error}=await sb.auth.signUp({email:$('signEmail').value.trim(),password:$('signPassword').value,options:{data:{full_name:$('signName').value.trim(),phone:$('signPhone').value.trim()},emailRedirectTo:cfg.AUTH_REDIRECT_URL||location.origin}});if(error){$('authMsg').innerHTML=`<div class="error">${esc(error.message)}</div>`;return}$('authMsg').innerHTML=`<div class="successmsg"><b>Verification email sent.</b><br>Check ${esc($('signEmail').value)} and click the verification link. Your account will not be available until the email is verified.</div>`}
async function login(e){e.preventDefault();$('authMsg').innerHTML='';let {data,error}=await sb.auth.signInWithPassword({email:$('loginEmail').value.trim(),password:$('loginPassword').value});if(error){$('authMsg').innerHTML=`<div class="error">${esc(error.message)}<br><button type="button" class="btn small" onclick="resendVerification()">Resend verification email</button></div>`;return}if(!data.user.email_confirmed_at){await sb.auth.signOut();$('authMsg').innerHTML='<div class="error"><b>Email verification not completed.</b><br>Please click the verification link sent to your email before logging in.</div>';return}setAuthUser(data);closeModal('auth');toast('Welcome back')}
async function resendVerification(){let email=$('loginEmail')?.value.trim();if(!email){toast('Enter your email first');return}let {error}=await sb.auth.resend({type:'signup',email});toast(error?error.message:'Verification email sent')}
async function resetPassword(){let email=prompt('Enter your email');if(!email)return;let {error}=await sb.auth.resetPasswordForEmail(email,{redirectTo:location.origin});toast(error?error.message:'Password reset email sent')}
function openAccount(){if(!currentUser){openAuth('login');return}renderAccount();openModal('account')}
async function renderAccount(){let {data:p,error:profileError}=await sb.from('profiles').select('*').eq('id',currentUser.id).maybeSingle();if(profileError){toast(profileError.message);p=currentProfile}currentProfile=p||currentProfile;updateNav();$('accountBody').innerHTML=`<div style="display:flex;align-items:center;gap:10px">${avatar(p?.avatar_url,p?.full_name||currentUser.email)}<div><b>${esc(p?.full_name||currentUser.email)}</b><br><small>${esc(currentUser.email)}</small></div></div><hr><div class="form"><input id="profileName" value="${esc(p?.full_name||'')}" placeholder="Full name"><input id="profilePhone" value="${esc(p?.phone||'')}" placeholder="Phone"><div id="profileImagePreview" style="margin:8px 0">${avatar(p?.avatar_url,p?.full_name||currentUser.email)}</div><input id="avatarFile" type="file" accept="image/*" onchange="previewProfileImage(this)"><button class="btn primary" onclick="saveProfile()">Save profile</button><button class="btn" onclick="openOrders()">My Orders</button>${isSeller?'<button class="btn" onclick="openSeller()">Seller Centre</button>':'<button class="btn" onclick="openSeller()">Become a seller</button>'}<button class="btn" onclick="manageAddresses()">Addresses</button><button class="btn danger" onclick="logout()">Log out</button></div>`}
function previewProfileImage(input){
 const f=input?.files?.[0];
 if(!f)return;
 if(!f.type.startsWith('image/')){toast('Please choose an image file');input.value='';return}
 if(f.size>5*1024*1024){toast('Profile picture must be 5 MB or smaller');input.value='';return}
 const reader=new FileReader();
 reader.onload=()=>{$('profileImagePreview').innerHTML=avatar(reader.result,$('profileName')?.value||currentUser?.email||'U')};
 reader.readAsDataURL(f);
}
async function saveProfile(){
 try{
   let url=currentProfile?.avatar_url||currentUser?.user_metadata?.avatar_url||null;
   let f=$('avatarFile').files[0];
   if(f){
     if(!f.type.startsWith('image/')){toast('Please choose an image file');return}
     if(f.size>5*1024*1024){toast('Profile picture must be 5 MB or smaller');return}
     let ext=(f.name.split('.').pop()||'jpg').toLowerCase();
     let path=`${currentUser.id}/${crypto.randomUUID()}.${ext}`;
     let up=await sb.storage.from('profile-photos').upload(path,f,{upsert:false});
     if(up.error)throw up.error;
     let publicResult=sb.storage.from('profile-photos').getPublicUrl(path);
url=(publicResult?.data?.publicUrl||'')+'?v='+Date.now();
if(!url || url==='?v='+Date.now())throw new Error('Could not create the profile picture URL');
   }
   let update={id:currentUser.id,full_name:$('profileName').value.trim(),phone:$('profilePhone').value.trim(),updated_at:new Date().toISOString()};
   if(url)update.avatar_url=url;
   let {data,error}=await sb.from('profiles').upsert(update,{onConflict:'id'}).select().single();
   if(error)throw error;
   currentProfile=data;
   currentUser.user_metadata={...currentUser.user_metadata,full_name:data.full_name,avatar_url:data.avatar_url};
   updateNav();
   toast('Profile saved');
   renderAccount();
 }catch(e){toast(e.message||'Could not save profile')}
}

async function loadAddresses(){
  if(!currentUser){addresses=[];return []}
  const {data,error}=await sb.from('addresses')
    .select('id,label,recipient_name,phone,line1,line2,city,postal_code,country,address_text,is_default,created_at,updated_at')
    .eq('user_id',currentUser.id)
    .order('is_default',{ascending:false})
    .order('created_at',{ascending:false});
  if(error) throw new Error(error.message);
  addresses=data||[];
  return addresses;
}
function addressFormMarkup(){
 return `<form class="form" onsubmit="saveNewAddress(event)">
   <input id="addrLabel" placeholder="Label (e.g. Home)" value="Home" required>
   <input id="addrName" placeholder="Recipient name" required>
   <input id="addrPhone" placeholder="Phone number" required>
   <input id="addrLine1" placeholder="Address / street" required>
   <input id="addrLine2" placeholder="Apartment, building, landmark (optional)">
   <input id="addrCity" placeholder="City / village" required>
   <input id="addrPostal" placeholder="Postal code (optional)">
   <label><input id="addrDefault" type="checkbox" checked> Make this my default address</label>
   <button class="btn primary" type="submit">Save address</button>
   <button class="btn" type="button" onclick="loadAddresses().then(()=>{if($('addressList'))renderAddressList();else manageAddresses()})">Cancel</button>
 </form>`;
}
function addAddressForm(){
  if($('addressList')){
    $('addressList').innerHTML=`<div class="order" style="margin-bottom:10px"><b>Add delivery address</b>${addressFormMarkup()}</div>`;
    return;
  }
  const body=$('accountBody');
  if(!body)return;
  body.innerHTML=`<h3>Delivery address</h3>${addressFormMarkup()}`;
}
function renderAddressList(){
  const el=$('addressList');
  if(!el)return;
  if(!addresses.length){
    el.innerHTML='<div class="notice">No delivery address saved. Add one before placing your order.</div>';
    return;
  }
  el.innerHTML=addresses.map(a=>`
    <label class="order" style="display:block;cursor:pointer;margin-bottom:8px">
      <input type="radio" name="addr" value="${esc(a.id)}" ${a.is_default?'checked':''}>
      <b>${esc(a.label||'Address')}</b> — ${esc(a.recipient_name||'')}
      <div>${esc(a.line1||'')}${a.line2?`, ${esc(a.line2)}`:''}<br>${esc(a.city||'')}${a.postal_code?`, ${esc(a.postal_code)}`:''}</div>
      <small>${esc(a.phone||'')}</small>
    </label>`).join('');
}
async function saveNewAddress(event){
  event.preventDefault();
  const values={
    p_id:null,
    p_label:$('addrLabel').value.trim()||'Home',
    p_name:$('addrName').value.trim(),
    p_phone:$('addrPhone').value.trim(),
    p_line1:$('addrLine1').value.trim(),
    p_line2:$('addrLine2').value.trim(),
    p_city:$('addrCity').value.trim(),
    p_postal:$('addrPostal').value.trim(),
    p_default:$('addrDefault').checked
  };
  if(!values.p_name||!values.p_phone||!values.p_line1||!values.p_city){
    toast('Please complete the required address fields'); return;
  }
  const {error}=await sb.rpc('save_shopora_address',values);
  if(error){toast(error.message||'Could not save address');return}
  await loadAddresses();
  toast('Address saved');
  if($('addressList')) renderAddressList();
  else manageAddresses();
}
async function manageAddresses(){
  await loadAddresses();
  const body=$('accountBody'); if(!body)return;
  body.innerHTML=`<h3>Delivery addresses</h3>
    <div id="addressList">${addresses.map(a=>`<div class="order">
      <b>${esc(a.label||'Address')}</b>
      <p>${esc(a.recipient_name||'')} · ${esc(a.phone||'')}<br>${esc(a.line1||'')}${a.line2?`, ${esc(a.line2)}`:''}, ${esc(a.city||'')}${a.postal_code?`, ${esc(a.postal_code)}`:''}</p>
      <button class="btn danger small" onclick="deleteAddress('${a.id}')">Delete</button>
    </div>`).join('')||'<div class="notice">No delivery address saved.</div>'}</div>
    <button class="btn primary" onclick="addAddressForm()">Add address</button>`;
}
async function deleteAddress(id){
 if(!confirm('Delete this delivery address?'))return;
 let {error}=await sb.rpc('delete_shopora_address',{p_id:id});
 if(error){
   toast(error.message?.includes('foreign key')||error.message?.includes('orders_address')
     ?'This address is linked to an order. The order will keep its delivery details, then the address can be deleted after the database migration is applied.'
     :error.message);
   return;
 }
 await manageAddresses();
 toast('Address deleted');
}
async function logout(){await sb.auth.signOut();currentUser=null;session=null;closeAll();updateNav();toast('Logged out')}

async function openSeller(){
 if(!currentUser){openAuth('login');return}
 try{
   let {data,error}=await sb.from('shops').select('*').eq('owner_id',currentUser.id).maybeSingle();
   if(error)throw error;
   if(!data){openSellerOnboarding();return}
   isSeller=true;shopData=data;setPageMode('seller');
   await loadSellerProducts();
   await loadSellerOrders();
   sellerTab='dashboard';
   renderSeller();
   openModal('seller');
 }catch(e){
   console.error('openSeller',e);
   toast(e.message||'Could not open Seller Centre');
 }
}
function openSellerOnboarding(){
 if(!currentUser){openAuth('login');return}
 closeAll();
 $('sellerBody').innerHTML=`<div class="seller-onboarding">
   <div class="onboard-icon">🏪</div>
   <h2>Become a seller</h2>
   <p class="muted">Create your store and start listing products. You can add your logo, cover photo, payment methods and products after setup.</p>
   <div class="form">
     <input id="onboardShopName" placeholder="Shop name" maxlength="80">
     <input id="onboardShopPhone" placeholder="Business phone" maxlength="30">
     <input id="onboardShopAddress" placeholder="Business / pickup address">
     <textarea id="onboardShopDesc" rows="4" placeholder="Tell customers about your shop"></textarea>
     <div class="notice">You can configure your shop logo, cover photo, shipping and payment methods in Seller Centre after creating the shop.</div>
     <button class="btn primary" onclick="createSellerShop()">Create my shop</button>
     <button class="btn" onclick="closeModal('seller')">Cancel</button>
   </div>
 </div>`;
 setPageMode('seller');
 openModal('seller');
}
async function createSellerShop(){
 try{
   if(!currentUser){openAuth('login');return}
   const name=$('onboardShopName').value.trim();
   if(name.length<2){toast('Enter a shop name');return}
   const {data,error}=await sb.rpc('save_shopora_shop',{
     p_name:name,
     p_description:$('onboardShopDesc').value.trim(),
     p_address:$('onboardShopAddress').value.trim(),
     p_phone:$('onboardShopPhone').value.trim(),
     p_logo:'',
     p_cover:'',
     p_shipping:0,
     p_free:null
   });
   if(error)throw error;
   isSeller=true;shopData=data;
   toast('Your shop was created');
   await loadSellerProducts();await loadSellerOrders();
   sellerTab='dashboard';renderSeller();setPageMode('seller');
 }catch(e){toast(e.message||'Could not create your shop')}
}
async function loadSellerProducts(){let {data,error}=await sb.rpc('get_shopora_seller_products',{});if(error)toast(error.message);sellerProducts=data||[]}
async function loadSellerOrders(){
 let {data,error}=await sb.rpc('get_shopora_seller_orders',{p_status:null,p_search:''});
 if(error){sellerOrders=[];toast(error.message);return false}
 sellerOrders=data||[];return true
}

function sellerReportRows(){
  const from=$('reportFrom')?.value||'';
  const to=$('reportTo')?.value||'';
  const status=$('reportStatus')?.value||'';
  const payment=$('reportPayment')?.value||'';
  const search=($('reportSearch')?.value||'').trim().toLowerCase();
  const fromTs=from?new Date(from+'T00:00:00'):null;
  const toTs=to?new Date(to+'T23:59:59.999'):null;

  return (sellerOrders||[]).filter(o=>{
    const d=new Date(o.created_at||0);
    if(fromTs && d<fromTs)return false;
    if(toTs && d>toTs)return false;
    if(status && String(o.status||'')!==status)return false;
    if(payment && String(o.payment_status||'')!==payment)return false;
    if(search){
      const hay=[
        o.order_number,o.customer_name,o.customer_phone,o.payment_method,
        ...(o.items||[]).map(i=>i.name)
      ].join(' ').toLowerCase();
      if(!hay.includes(search))return false;
    }
    return true;
  });
}
function reportStatusLabel(v){return String(v||'pending').replaceAll('_',' ')}
function reportDate(v){
  if(!v)return '';
  const d=new Date(v); return Number.isNaN(d.getTime())?'':d.toLocaleString('en-MU');
}
function sellerReportsView(){
  const rows=sellerReportRows();
  const itemCount=rows.reduce((n,o)=>n+(o.items||[]).reduce((a,i)=>a+Number(i.quantity||0),0),0);
  const total=rows.reduce((n,o)=>n+Number(o.total||0),0);
  return `<h2>Sales reports</h2>
  <div class="notice">Generate an Excel-compatible report for your shop. Filter by date, order status, payment status or product/customer, then export.</div>
  <div class="form">
    <div class="formgrid">
      <div><label>From date</label><input id="reportFrom" type="date" onchange="refreshSellerReport()"></div>
      <div><label>To date</label><input id="reportTo" type="date" onchange="refreshSellerReport()"></div>
    </div>
    <div class="formgrid">
      <div><label>Order status</label><select id="reportStatus" onchange="refreshSellerReport()">
        <option value="">All statuses</option>
        <option value="payment_pending">Payment pending</option>
        <option value="processing">Processing</option>
        <option value="packed">Packed</option>
        <option value="shipped">Shipped</option>
        <option value="delivered">Delivered</option>
        <option value="completed">Completed</option>
        <option value="cancelled">Cancelled</option>
      </select></div>
      <div><label>Payment status</label><select id="reportPayment" onchange="refreshSellerReport()">
        <option value="">All payments</option>
        <option value="pending">Payment pending</option>
        <option value="paid">Paid</option>
        <option value="rejected">Rejected</option>
      </select></div>
    </div>
    <div class="formgrid">
      <div><label>Search</label><input id="reportSearch" placeholder="Order, customer or product" oninput="refreshSellerReport()"></div>
      <div><label>Quick period</label><select id="reportPreset" onchange="applyReportPreset()">
        <option value="">Custom dates</option>
        <option value="today">Today</option>
        <option value="yesterday">Yesterday</option>
        <option value="7">Last 7 days</option>
        <option value="30">Last 30 days</option>
        <option value="month">This month</option>
      </select></div>
    </div>
    <div class="cardactions">
      <button class="btn" onclick="clearSellerReportFilters()">Clear filters</button>
      <button class="btn primary" onclick="exportSellerReport()">📊 Export Excel report</button>
    </div>
  </div>
  <div id="sellerReportSummary" class="statgrid" style="margin-top:15px">
    <div class="stat"><small>Orders</small><b>${rows.length}</b></div>
    <div class="stat"><small>Items sold</small><b>${itemCount}</b></div>
    <div class="stat"><small>Order value</small><b>${money(total)}</b></div>
    <div class="stat"><small>Pending delivery</small><b>${rows.filter(o=>['payment_pending','processing','packed','shipped'].includes(o.status)).length}</b></div>
  </div>
  <div id="sellerReportPreview" style="margin-top:15px">${renderSellerReportPreview(rows)}</div>`;
}
function renderSellerReportPreview(rows){
  if(!rows.length)return '<div class="empty">No orders match the selected filters.</div>';
  return `<div class="tablewrap"><table class="report-table"><thead><tr>
    <th>Date</th><th>Order</th><th>Customer</th><th>Products</th><th>Qty</th><th>Total</th><th>Payment</th><th>Status</th>
  </tr></thead><tbody>${rows.slice(0,100).map(o=>`
    <tr><td>${esc(reportDate(o.created_at))}</td>
    <td>${esc(o.order_number||'')}</td>
    <td>${esc(o.customer_name||'')}<br><small>${esc(o.customer_phone||'')}</small></td>
    <td>${(o.items||[]).map(i=>esc(i.name||'Product')+' × '+Number(i.quantity||0)).join('<br>')}</td>
    <td>${(o.items||[]).reduce((n,i)=>n+Number(i.quantity||0),0)}</td>
    <td>${money(o.total)}</td>
    <td>${esc(o.payment_status||'pending')}</td>
    <td>${esc(reportStatusLabel(o.status))}</td></tr>`).join('')}</tbody></table>${rows.length>100?`<p class="muted">Showing first 100 orders. The Excel export contains all ${rows.length} matching orders.</p>`:''}</div>`;
}
function refreshSellerReport(){
  const rows=sellerReportRows();
  const summary=$('sellerReportSummary'),preview=$('sellerReportPreview');
  if(summary){
    const itemCount=rows.reduce((n,o)=>n+(o.items||[]).reduce((a,i)=>a+Number(i.quantity||0),0),0);
    const total=rows.reduce((n,o)=>n+Number(o.total||0),0);
    summary.innerHTML=`<div class="stat"><small>Orders</small><b>${rows.length}</b></div>
      <div class="stat"><small>Items sold</small><b>${itemCount}</b></div>
      <div class="stat"><small>Order value</small><b>${money(total)}</b></div>
      <div class="stat"><small>Pending delivery</small><b>${rows.filter(o=>['payment_pending','processing','packed','shipped'].includes(o.status)).length}</b></div>`;
  }
  if(preview)preview.innerHTML=renderSellerReportPreview(rows);
}
function localDateInput(d){
  const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,'0'),day=String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}
function applyReportPreset(){
  const p=$('reportPreset')?.value;
  if(!p)return;
  const now=new Date(), to=new Date(now), from=new Date(now);
  if(p==='yesterday'){from.setDate(from.getDate()-1);to.setDate(to.getDate()-1)}
  else if(p==='7')from.setDate(from.getDate()-6);
  else if(p==='30')from.setDate(from.getDate()-29);
  else if(p==='month')from.setDate(1);
  if($('reportFrom'))$('reportFrom').value=localDateInput(from);
  if($('reportTo'))$('reportTo').value=localDateInput(to);
  refreshSellerReport();
}
function clearSellerReportFilters(){
  ['reportFrom','reportTo','reportSearch'].forEach(id=>{if($(id))$(id).value=''});
  ['reportStatus','reportPayment','reportPreset'].forEach(id=>{if($(id))$(id).value=''});
  refreshSellerReport();
}
function excelEscape(v){
  return String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function exportSellerReport(){
  const rows=sellerReportRows();
  if(!rows.length){toast('No orders match the selected filters');return}
  const from=$('reportFrom')?.value||'All';
  const to=$('reportTo')?.value||'All';
  const orderRows=[],itemRows=[];
  rows.forEach(o=>{
    const delivery=o.delivery||{};
    const address=[delivery.line1||delivery.address_text,delivery.line2,delivery.city,delivery.postal_code].filter(Boolean).join(', ');
    orderRows.push([
      reportDate(o.created_at),o.order_number,o.customer_name,o.customer_phone,
      o.status,o.payment_status,o.payment_method||'',o.payment_details||'',
      o.subtotal,o.shipping,o.total,o.tracking_number||'',o.carrier||'',address
    ]);
    (o.items||[]).forEach(i=>itemRows.push([
      reportDate(o.created_at),o.order_number,o.customer_name,o.customer_phone,
      i.name||'Product',Number(i.quantity||0),Number(i.price||0),
      Number(i.price||0)*Number(i.quantity||0),o.payment_status,o.status
    ]));
  });
  const escCell=v=>`<td>${excelEscape(v)}</td>`;
  const table=(headers,data)=>`<table border="1"><thead><tr>${headers.map(h=>`<th>${excelEscape(h)}</th>`).join('')}</tr></thead><tbody>${data.map(r=>`<tr>${r.map(escCell).join('')}</tr>`).join('')}</tbody></table>`;
  const htmlDoc=`<html><head><meta charset="UTF-8"></head><body>
    <h2>Shopora Sales Report</h2>
    <p>Shop: ${excelEscape(shopData?.name||shopData?.shop_name||'')}</p>
    <p>Period: ${excelEscape(from)} to ${excelEscape(to)}</p>
    <h3>Orders</h3>
    ${table(['Date','Order number','Customer','Phone','Order status','Payment status','Payment method','Payment details','Subtotal MUR','Shipping MUR','Total MUR','Tracking number','Carrier','Delivery address'],orderRows)}
    <br><h3>Purchased goods</h3>
    ${table(['Date','Order number','Customer','Phone','Product','Quantity','Unit price MUR','Line total MUR','Payment status','Order status'],itemRows)}
  </body></html>`;
  const blob=new Blob(['\ufeff',htmlDoc],{type:'application/vnd.ms-excel;charset=utf-8'});
  const url=URL.createObjectURL(blob);
  const a=document.createElement('a');
  const stamp=localDateInput(new Date()).replaceAll('-','');
  a.href=url;a.download=`Shopora-Sales-Report-${stamp}.xls`;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
  toast(`Excel report generated: ${rows.length} orders`);
}
function sellerDashboard(){let revenue=sellerOrders.filter(o=>o.payment_status==='paid').reduce((a,o)=>a+Number(o.total),0),pending=sellerOrders.filter(o=>o.status==='payment_pending').length,packed=sellerOrders.filter(o=>o.status==='packed').length;return `<h2>Seller dashboard</h2><div class="statgrid"><div class="stat"><small>Revenue</small><b>${money(revenue)}</b></div><div class="stat"><small>Total orders</small><b>${sellerOrders.length}</b></div><div class="stat"><small>Payment pending</small><b>${pending}</b></div><div class="stat"><small>Packed</small><b>${packed}</b></div></div><div class="notice" style="margin-top:15px">Your seller account is connected to Shopora's order, inventory and notification system.</div>`}
function sellerShop(){let s=shopData||{};return `<h2>Shop profile</h2><div class="form">
<div class="formgrid"><input id="shopName" value="${esc(s.name||'')}" placeholder="Shop name"><input id="shopPhone" value="${esc(s.phone||'')}" placeholder="Shop phone"></div>
<input id="shopAddress" value="${esc(s.address||'')}" placeholder="Shop address">
<textarea id="shopDesc" rows="4" placeholder="Shop description">${esc(s.description||'')}</textarea>

<div class="media-editor">
  <div class="media-box">
    <h3>Shop logo</h3>
    <p class="muted">Shown beside your shop name.</p>
    <div id="shopLogoPreview" class="shop-media-preview">${s.logo_url?`<img src="${esc(s.logo_url)}" alt="Shop logo">`:'<span>No logo uploaded</span>'}</div>
    <input id="shopLogo" type="file" accept="image/jpeg,image/png,image/webp" onchange="previewShopMedia(this,'shopLogoPreview','logo')">
  </div>
  <div class="media-box">
    <h3>Shop cover photo</h3>
    <p class="muted">Large banner displayed at the top of your store.</p>
    <div id="shopCoverPreview" class="shop-cover-preview">${s.cover_url?`<img src="${esc(s.cover_url)}" alt="Shop cover photo">`:'<span>No cover photo uploaded</span>'}</div>
    <input id="shopCover" type="file" accept="image/jpeg,image/png,image/webp" onchange="previewShopMedia(this,'shopCoverPreview','cover')">
  </div>
</div>

<div class="notice">Recommended cover size: <b>1600 × 500 px</b>. JPG, PNG or WebP, maximum 10 MB.</div>
<div class="formgrid"><input id="shipFee" type="number" min="0" step="0.01" value="${Number(s.shipping_fee||0)}" placeholder="Shipping fee (MUR)"><input id="freeShip" type="number" min="0" step="0.01" value="${s.free_shipping_from??''}" placeholder="Free shipping from (MUR)"></div>
<button class="btn primary" onclick="saveShop()">Save shop</button>
</div>`}

function previewShopMedia(input,targetId,type){
 const f=input?.files?.[0]; if(!f)return;
 if(!/^image\/(jpeg|png|webp)$/.test(f.type)){toast('Please choose a JPG, PNG or WebP image');input.value='';return}
 if(f.size>10*1024*1024){toast('Image must be 10 MB or smaller');input.value='';return}
 const reader=new FileReader();
 reader.onload=()=>{$(targetId).innerHTML=`<img src="${reader.result}" alt="${type==='cover'?'Shop cover photo':'Shop logo'}">`};
 reader.readAsDataURL(f);
}

async function uploadPublic(bucket,file,folder){if(!file)return null;let path=`${folder}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;let {error}=await sb.storage.from(bucket).upload(path,file,{upsert:true});if(error)throw error;return sb.storage.from(bucket).getPublicUrl(path).data.publicUrl}
async function saveShop(){
 try{
  const name=($('shopName')?.value||'').trim();
  if(!name){toast('Enter your shop name');$('shopName')?.focus();return}
  if(!currentUser?.id){toast('Please log in again');return}

  const logoFile=$('shopLogo')?.files?.[0],coverFile=$('shopCover')?.files?.[0];
  const logo=await uploadPublic('shop-media',logoFile,currentUser.id);
  const cover=await uploadPublic('shop-media',coverFile,currentUser.id);

  const payload={
   p_name:name,
   p_description:($('shopDesc')?.value||'').trim(),
   p_address:($('shopAddress')?.value||'').trim(),
   p_phone:($('shopPhone')?.value||'').trim(),
   p_logo:logo||shopData?.logo_url||'',
   p_cover:cover||shopData?.cover_url||'',
   p_shipping:Math.max(0,Number($('shipFee')?.value||0)),
   p_free:($('freeShip')?.value||'')!==''?Math.max(0,Number($('freeShip').value)):null
  };
  const {data,error}=await sb.rpc('save_shopora_shop',payload);
  if(error)throw error;
  shopData={...(data||{}),name:data?.name||data?.shop_name||name};
  toast('Shop profile saved successfully');
  sellerTab='shop';
  renderSeller();
 }catch(e){
  console.error('saveShop',e);
  toast(e?.message||'Could not save shop profile');
 }
}

function renderImagePreviews(urls){
 let box=$('imagePreview');if(!box)return;
 box.innerHTML=(urls||[]).slice(0,5).map(u=>`<img src="${esc(u)}" alt="Product image">`).join('');
}
function validateProductImages(){
 let input=$('spImages'),files=[...(input?.files||[])],help=$('imageHelp');
 if(files.length>5){toast('You can upload a maximum of 5 pictures');input.value='';if(help)help.textContent='Upload 2–5 clear pictures.';return false}
 if(files.length>0)renderImagePreviews(files.map(f=>URL.createObjectURL(f)));
 if(help)help.textContent=files.length===0?'Upload 2–5 clear pictures.':`${files.length} picture${files.length===1?'':'s'} selected.`;
 return true;
}
async function saveProduct(id){
 try{
   let files=[...$('spImages').files];
   const name=$('spName').value.trim();
   const price=Number($('spPrice').value);
   const stock=Number($('spStock').value);
   if(!name){toast('Enter a product name');return}
   if(!Number.isFinite(price)||price<=0){toast('Enter a valid price greater than 0 MUR');return}
   if(!Number.isInteger(stock)||stock<0){toast('Enter a valid whole-number stock quantity');return}
   if(files.length>5){toast('Maximum 5 pictures allowed');return}
   if(!id && files.length<2){toast('Please upload at least 2 pictures for a new product');return}
   if(id && files.length===1){toast('Please select 2–5 pictures when replacing product pictures');return}
   if(files.some(f=>!f.type.startsWith('image/'))){toast('Only image files are allowed');return}
   let urls=[];
   for(let f of files){
     if(f.size>10*1024*1024){toast(`${f.name} is larger than 10 MB`);return}
     let u=await uploadPublic('product-images',f,currentUser.id);urls.push(u)
   }
   const categoryId=$('spCat').value||null;
   if(categoryId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(categoryId)){
    toast('Please select a valid category');
    return;
   }
   let {error}=await sb.rpc('save_shopora_product_v46',{
     p_product:id||null,
     p_name:name,
     p_category:categoryId,
     p_price:price,
     p_compare:null,
     p_stock:stock,
     p_description:$('spDesc').value.trim(),
     p_brand:$('spBrand').value.trim(),
     p_sku:$('spSku').value.trim(),
     p_images:urls
   });
   if(error)throw error;
   await loadSellerProducts();toast('Product saved');renderSeller()
 }catch(e){toast(e.message)}
}
async function deleteSellerProduct(id){if(!confirm('Delete this product?'))return;let {error}=await sb.rpc('delete_shopora_product',{p_product:id});if(error)toast(error.message);else{await loadSellerProducts();renderSeller()}}

function renderSeller(){
 const body=$('sellerBody'); if(!body)return;
 const tabs=[['dashboard','📊 Dashboard'],['shop','🏪 Shop profile'],['products','📦 Products'],['orders','🧾 Orders'],['reports','📈 Reports'],['payments','💳 Payments'],['returns','↩ Returns']];
 let content;
 if(sellerTab==='shop') content=sellerShop();
 else if(sellerTab==='products') content=sellerProductsView();
 else if(sellerTab==='orders') content=sellerOrderManager();
 else if(sellerTab==='reports') content=sellerReportsView();
 else if(sellerTab==='payments') content=sellerPaymentsView();
 else if(sellerTab==='returns') content=sellerReturns();
 else content=sellerDashboard();

 body.innerHTML=`<div class="seller-layout">
  <aside class="seller-sidebar">
   ${tabs.map(([id,label])=>`<button class="seller-nav ${sellerTab===id?'active':''}" onclick="openSellerTab('${id}')">${label}</button>`).join('')}
   <button class="seller-nav danger" onclick="logout()">↪ Log out</button>
  </aside>
  <main class="seller-main">${content}</main>
 </div>`;
}

function sellerProductsView(){
 return `<h2>Products</h2>
 <div class="notice">Manage the products in your store. New products require 2–5 pictures.</div>
 <button class="btn primary" onclick="openProductEditor()">＋ Add product</button>
 <div style="margin-top:14px">${(sellerProducts||[]).map(p=>`
  <div class="order" style="display:flex;align-items:center;justify-content:space-between;gap:12px">
   <div><b>${esc(p.name||'Product')}</b><br><small>${money(p.price_mur??p.price)} · Stock ${Number(p.stock||0)} · ${esc(p.status||'active')}</small></div>
   <div class="cardactions"><button class="btn" onclick="openProductEditor('${p.id}')">Edit</button><button class="btn danger" onclick="deleteSellerProduct('${p.id}')">Delete</button></div>
  </div>`).join('')||'<div class="empty">No products yet.</div>'}</div>`;
}

async function openProductEditor(id){
 try{
  let p=(sellerProducts||[]).find(x=>String(x.id)===String(id))||{};
  let categoryId=p.category_id||'';
  if(id && !categoryId){
   const {data,error}=await sb.from('products').select('category_id').eq('id',id).maybeSingle();
   if(error)throw error;
   categoryId=data?.category_id||'';
  }
  sellerTab='products';
  const opts=(categories||[]).map(c=>{
   const cid=String(c.id||'');
   const selected=cid===String(categoryId)?' selected':'';
   return `<option value="${esc(cid)}"${selected}>${esc(c.name||c.slug||'')}</option>`;
  }).join('');
  const form=`<h2>${id?'Edit product':'Add product'}</h2>
  <div class="form">
   <input id="spName" value="${esc(p.name||'')}" placeholder="Product name">
   <div class="formgrid"><input id="spPrice" type="number" min="0.01" step="0.01" value="${p.price_mur??p.price??''}" placeholder="Price (MUR)"><input id="spStock" type="number" min="0" step="1" value="${p.stock??0}" placeholder="Stock quantity"></div>
   <select id="spCat"><option value="">Category</option>${opts}</select>
   <div class="formgrid"><input id="spBrand" value="${esc(p.brand||'')}" placeholder="Brand (optional)"><input id="spSku" value="${esc(p.sku||'')}" placeholder="SKU (optional)"></div>
   <textarea id="spDesc" rows="5" placeholder="Product description">${esc(p.description||'')}</textarea>
   <label>Product pictures <b>(2–5)</b></label>
   <input id="spImages" type="file" accept="image/*" multiple onchange="validateProductImages()">
   <div id="imageHelp" class="muted">For a new product, select 2–5 pictures.</div>
   <div id="imagePreview" class="image-preview"></div>
   <button class="btn primary" onclick="saveProduct(${id?`'${id}'`:'null'})">Save product</button>
   <button class="btn" onclick="renderSeller()">Cancel</button>
  </div>`;
  $('sellerBody').innerHTML=`<div class="seller-layout"><aside class="seller-sidebar">${[['dashboard','📊 Dashboard'],['shop','🏪 Shop profile'],['products','📦 Products'],['orders','🧾 Orders'],['payments','💳 Payments'],['returns','↩ Returns']].map(([x,l])=>`<button class="seller-nav ${x==='products'?'active':''}" onclick="openSellerTab('${x}')">${l}</button>`).join('')}<button class="seller-nav danger" onclick="logout()">↪ Log out</button></aside><main class="seller-main">${form}</main></div>`;
  openModal('seller');setPageMode('seller');
 }catch(e){
  console.error('openProductEditor',e);
  toast(e?.message||'Could not open product editor');
 }
}

function sellerPaymentsView(){
 return `<h2>Payment methods</h2><div class="notice">Customers will see these payment instructions at checkout. You control your own business payment details.</div>
 <button class="btn primary" onclick="addPaymentMethod()">＋ Add payment method</button>
 <div style="margin-top:14px">${(shopData?.payment_methods||[]).map((m,i)=>renderSellerPayment(m,i)).join('')||'<div class="empty">No payment methods configured.</div>'}</div>`;
}

async function addPaymentMethod(){
 try{
  if(!currentUser?.id){toast('Please log in again');return}
  if(!shopData?.id){toast('Create and save your shop profile first');sellerTab='shop';renderSeller();return}
  const methods=MAURITIUS_BANKS;
  $('sellerBody').innerHTML=`<div class="seller-layout"><aside class="seller-sidebar">${[['dashboard','📊 Dashboard'],['shop','🏪 Shop profile'],['products','📦 Products'],['orders','🧾 Orders'],['payments','💳 Payments'],['returns','↩ Returns']].map(([x,l])=>`<button class="seller-nav ${x==='payments'?'active':''}" onclick="openSellerTab('${x}')">${l}</button>`).join('')}<button class="seller-nav danger" onclick="logout()">↪ Log out</button></aside><main class="seller-main"><h2>Add payment method</h2><div class="notice">Choose the bank/payment service and enter the business payment details customers should use.</div><div class="form"><label>Bank / payment service</label><select id="sellerPayBank" onchange="renderPaymentForm()">${methods.map(b=>`<option value="${esc(b.id)}">${esc(b.logo)} ${esc(b.name)}</option>`).join('')}<option value="custom">💳 Custom payment method</option></select><div id="sellerPayForm"></div><div class="cardactions"><button class="btn primary" onclick="savePaymentMethod()">Save payment method</button><button class="btn" onclick="renderSeller()">Cancel</button></div></div></main></div>`;
  renderPaymentForm();setPageMode('seller');
 }catch(e){console.error('addPaymentMethod',e);toast(e?.message||'Could not open payment method form')}
}
function renderCustomerOrder(o){
 const pk=o.packages||[];
 return `<div class="order">
  <div class="orderhead">
   <div><b>${esc(o.order_number||'Order')}</b><br><small>${o.created_at?new Date(o.created_at).toLocaleString():''}</small></div>
   <span class="status ${esc(o.status||'')}">${esc(String(o.status||'pending').replaceAll('_',' '))}</span>
  </div>
  <h3>${money(o.total)}</h3>
  ${pk.map(p=>`<div class="order" style="background:#f8fafc">
    <div class="orderhead"><b>${esc(p.shop_name||'Seller')}</b><span class="status ${esc(p.status||'')}">${esc(String(p.status||'pending').replaceAll('_',' '))}</span></div>
    <p>${(p.items||[]).map(i=>`${esc(i.name||'Product')} × ${Number(i.quantity||0)}`).join(' · ')||'No items'}</p>
    <p>Payment: <b>${esc(p.payment_status||o.payment_status||'pending')}</b></p>
    ${p.tracking?`<p>Tracking: <b>${esc(p.tracking)}</b>${p.carrier?` · ${esc(p.carrier)}`:''}</p>`:''}
    ${p.status==='delivered'||p.status==='shipped'?`<button class="btn success" onclick="confirmReceived('${p.id}')">✓ Confirm received</button>`:''}
    ${p.status==='completed'?'<span class="status completed">✓ Received</span>':''}
  </div>`).join('')||'<div class="empty">No seller package information.</div>'}
 </div>`;
}

function renderSellerOrders(list){
 return (list||[]).map(o=>`<div class="order">
  <div class="orderhead">
   <div><b>${esc(o.order_number||'Order')}</b><br>${esc(o.customer_name||'Customer')} · ${esc(o.customer_phone||'')}</div>
   <span class="status ${esc(o.status||'')}">${esc(String(o.status||'pending').replaceAll('_',' '))}</span>
  </div>
  <p>${(o.items||[]).map(i=>`${esc(i.name||'Product')} × ${Number(i.quantity||0)}`).join(' · ')||'No items'}</p>
  <p><b>${money(o.total)}</b> · Payment: <span class="status ${esc(o.payment_status||'')}">${esc(o.payment_status||'pending')}</span></p>
  <p>${esc(o.delivery?.line1||o.delivery?.address_text||'')}${o.delivery?.city?', '+esc(o.delivery.city):''}</p>
  <div class="cardactions">
   ${o.payment_status==='pending'?`<button class="btn success" onclick="sellerAction('${o.seller_order_id}','payment')">✓ Payment completed</button>`:''}
   ${o.payment_status==='paid'&&['processing','payment_pending'].includes(o.status)?`<button class="btn" onclick="sellerAction('${o.seller_order_id}','packed')">📦 Pack order</button>`:''}
   ${o.status==='packed'?`<button class="btn primary" onclick="shipOrder('${o.seller_order_id}')">🚚 Ship order</button>`:''}
   ${o.status==='shipped'?`<button class="btn" onclick="sellerAction('${o.seller_order_id}','delivered')">Mark delivered</button>`:''}
  </div>
  ${o.tracking_number?`<small>Tracking: ${esc(o.tracking_number)}${o.carrier?` · ${esc(o.carrier)}`:''}</small>`:''}
 </div>`).join('')||'<div class="empty">No orders.</div>';
}

async function sellerAction(id,action){
 if(!id)return;
 try{
  if(action==='payment'){
   if(!confirm('Confirm that payment has been received for this order?'))return;
   const {error}=await sb.rpc('seller_confirm_shopora_payment',{p_seller_order:id});
   if(error)throw error;
  }else{
   const {error}=await sb.rpc('seller_set_shopora_order_status',{
    p_seller_order:id,p_status:action,p_tracking:null,p_carrier:null,p_note:null
   });
   if(error)throw error;
  }
  toast(action==='payment'?'Payment confirmed':`Order marked ${action}`);
  await loadSellerOrders();renderSeller();
 }catch(e){toast(e.message||'Could not update order')}
}

async function shipOrder(id){
 const tracking=prompt('Tracking number (optional):','');
 if(tracking===null)return;
 const carrier=prompt('Carrier / delivery service (optional):','');
 if(carrier===null)return;
 try{
  const {error}=await sb.rpc('seller_set_shopora_order_status',{
   p_seller_order:id,p_status:'shipped',
   p_tracking:tracking.trim()||null,p_carrier:carrier.trim()||null,p_note:null
  });
  if(error)throw error;
  toast('Order shipped');
  await loadSellerOrders();renderSeller();
 }catch(e){toast(e.message||'Could not ship order')}
}

async function packAllPaid(){
 const a=(sellerOrders||[]).filter(o=>o.payment_status==='paid'&&['processing','payment_pending'].includes(o.status));
 if(!a.length){toast('No paid orders waiting to pack');return}
 if(!confirm(`Pack ${a.length} order(s)?`))return;
 for(const o of a){
  const {error}=await sb.rpc('seller_set_shopora_order_status',{
   p_seller_order:o.seller_order_id,p_status:'packed',p_tracking:null,p_carrier:null,p_note:null
  });
  if(error){toast(error.message);return}
 }
 await loadSellerOrders();renderSeller();toast('Paid orders packed');
}

function sellerOrderManager(){return `<h2>Order Manager</h2>
<div class="notice">All orders from your shop appear here. Confirm payment first, then pack and ship the order. Customers can confirm receipt after delivery.</div>
<div class="filters">
 <input id="sellerSearch" placeholder="Search order/customer" oninput="filterSellerOrders()">
 <select id="sellerStatus" onchange="filterSellerOrders()"><option value="">All statuses</option><option value="payment_pending">Payment pending</option><option value="processing">Processing</option><option value="packed">Packed</option><option value="shipped">Shipped</option><option value="delivered">Delivered</option><option value="completed">Completed</option></select>
 <button class="btn" onclick="loadSellerOrders().then(()=>renderSeller())">Refresh</button>
</div>
<div id="sellerOrdersList">${renderSellerOrders(sellerOrders)}</div>`}
function renderSellerPayment(m,i){
 let bank=MAURITIUS_BANKS.find(b=>b.id===m.bank);
 let title=m.bank==='custom'?(m.name||'Payment method'):(bank?.name||m.name||'Payment method');
 let detail=m.type==='juice'?`MCB Juice: ${m.juice_number||''}`:m.account_number?`Account: ${m.account_number}`:(m.details||'');
 return `<div class="order" style="display:flex;justify-content:space-between;align-items:center;gap:14px;margin-bottom:10px">
   <div style="display:flex;align-items:center;gap:12px"><span class="bankLogo">${esc(bank?.logo||'💳')}</span><div><b>${esc(title)}</b><p style="margin:5px 0 0">${esc(detail)}</p>${m.holder_name?`<small>Account holder: ${esc(m.holder_name)}</small>`:''}</div></div>
   <button class="btn danger small" onclick="removePayment(${i})">Remove</button>
 </div>`;
}
function renderPaymentForm(){
 let id=$('sellerPayBank')?.value||'mcb',b=MAURITIUS_BANKS.find(x=>x.id===id);
 let form=$('sellerPayForm');if(!form)return;
 if(id==='custom'){
   form.innerHTML=`<div class="formgrid"><input id="customPayName" placeholder="Payment method name (e.g. Cash on delivery)"><input id="customPayDetails" placeholder="Payment instructions"></div>`;
 }else if(id==='mcb'){
   form.innerHTML=`<label>MCB payment type</label><select id="mcbPayType" onchange="renderMcbFields()"><option value="account">MCB Account number</option><option value="juice">MCB Juice number</option></select><div id="mcbFields" style="margin-top:10px"></div>`;
   renderMcbFields();
 }else{
   form.innerHTML=`<input id="bankAccountNumber" inputmode="numeric" placeholder="${esc(b.name)} account number"><input id="bankHolderName" style="margin-top:10px" placeholder="Account holder / business name">`;
 }
}
function renderMcbFields(){
 let type=$('mcbPayType')?.value||'account',form=$('mcbFields');if(!form)return;
 form.innerHTML=type==='juice'
  ? `<input id="mcbJuiceNumber" inputmode="numeric" placeholder="MCB Juice mobile number"><input id="mcbHolderName" style="margin-top:10px" placeholder="Account / business name">`
  : `<input id="mcbAccountNumber" inputmode="numeric" placeholder="MCB account number"><input id="mcbHolderName" style="margin-top:10px" placeholder="Account / business name">`;
}
async function savePaymentMethod(){
 try{
  if(!shopData?.id){toast('Create and save your shop profile first');return}
  let id=$('sellerPayBank')?.value||'mcb',b=MAURITIUS_BANKS.find(x=>x.id===id),m;
  if(id==='custom'){
   let name=$('customPayName')?.value.trim(),details=$('customPayDetails')?.value.trim();
   if(!name||!details){toast('Enter the payment method name and instructions');return}
   m={bank:'custom',name,details,type:'custom'};
  }else if(id==='mcb'){
   let type=$('mcbPayType')?.value||'account',holder=$('mcbHolderName')?.value.trim();
   if(!holder){toast('Enter the account holder / business name');return}
   if(type==='juice'){
    let juice=$('mcbJuiceNumber')?.value.trim();
    if(!juice){toast('Enter your MCB Juice number');return}
    m={bank:'mcb',name:'MCB Juice',type:'juice',juice_number:juice,holder_name:holder,details:`MCB Juice: ${juice}`};
   }else{
    let account=$('mcbAccountNumber')?.value.trim();
    if(!account){toast('Enter your MCB account number');return}
    m={bank:'mcb',name:'MCB Bank Account',type:'account',account_number:account,holder_name:holder,details:`MCB Account: ${account}`};
   }
  }else{
   let account=$('bankAccountNumber')?.value.trim(),holder=$('bankHolderName')?.value.trim();
   if(!account||!holder){toast('Enter the account number and account holder / business name');return}
   m={bank:id,name:b?.name||id,type:'account',account_number:account,holder_name:holder,details:`${b?.name||id} Account: ${account}`};
  }
  const methods=[...(shopData.payment_methods||[]),m];
  const {data,error}=await sb.rpc('save_shopora_payment_methods',{p_methods:methods});
  if(error)throw error;
  shopData={...(data||{}),name:data?.name||data?.shop_name||shopData.name,payment_methods:data?.payment_methods||methods};
  toast('Payment method added successfully');
  sellerTab='payments';renderSeller();
 }catch(e){console.error('savePaymentMethod',e);toast(e?.message||'Could not save payment method')}
}
async function removePayment(i){
 let m=[...(shopData.payment_methods||[])];m.splice(i,1);
 let {data,error}=await sb.rpc('save_shopora_payment_methods',{p_methods:m});
 if(error)toast(error.message);else{shopData={...(data||{}),name:data?.name||data?.shop_name||shopData?.name||''};toast('Payment method removed');renderSeller()}
}
function sellerReturns(){return `<h2>Returns & refunds</h2><div class="notice">Return requests appear here when customers request a return. The next production phase can connect approved returns to your chosen refund provider.</div>`}
function filterSellerOrders(){
 const q=($('sellerSearch')?.value||'').toLowerCase(),st=$('sellerStatus')?.value||'';
 const list=sellerOrders.filter(o=>(!q||`${o.order_number} ${o.customer_name} ${o.customer_phone}`.toLowerCase().includes(q))&&(!st||o.status===st));
 if($('sellerOrdersList'))$('sellerOrdersList').innerHTML=renderSellerOrders(list);
}
async function init(){
 try{
   if(!cfg.SUPABASE_URL||!cfg.SUPABASE_PUBLISHABLE_KEY)throw new Error('Supabase configuration is missing');
   let {data,error}=await sb.auth.getSession();
   if(error)throw error;
   await setAuthUser(data.session);
   sb.auth.onAuthStateChange((_e,s)=>{
     setAuthUser(s);
     if(s?.user&&!s.user.email_confirmed_at){
       sb.auth.signOut();
       toast('Please verify your email before using your account.');
     }
   });
   try{ await loadCategories(); }catch(e){ console.error('Homepage categories:',e); }
   try{ await loadCatalog(); }catch(e){ console.error('Homepage products:',e); }
   saveCart();
 }catch(e){
   console.error('Shopora startup error:',e);
   toast(e?.message||'Shopora could not connect to the database');
   if($('categories') && !$('categories').children.length)$('categories').innerHTML='<div class="empty">Unable to load categories. Check your Supabase connection.</div>';
   if($('products') && !$('products').children.length)$('products').innerHTML='<div class="empty">Unable to load products. Check your Supabase connection.</div>';
 }
}
init();
