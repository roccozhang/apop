function QMSW__addEvent() {
	var url = "1.jpg";
	var href = "http://www.baidu.com";
	var _h = 150; //图片的最大高度

	var div = document.createElement("div");
	div.id = "QMSW__maskBig_div";
	div.style.position = "fixed";
	div.style.bottom = "0px";
	div.style.left = "0px";
	
	var img = document.createElement("img");
	img.src = url;
	img.style.margin = "0 auto"
	img.style.display = "none";

	var close = document.createElement("div");
	close.innerHTML = "X";
	close.style.textAlign = "center";
	close.style.lineHeight = "20px"
	close.style.width = "20px";
	close.style.height = "20px";
	close.style.background = "#ccc";
	close.style.color = "#38b5cc";
	close.style.position = "absolute";
	close.style.top = "0";
	close.style.left = "0";
	close.style.cursor = "pointer";
	close.onclick = function() {
		var qmsw = document.getElementById("QMSW__maskBig_div");
		qmsw.remove();
	}

	var link = document.createElement("a");
	link.href = href;

	div.appendChild(close);
	div.appendChild(link);
	link.appendChild(img);
	document.getElementsByTagName("body")[0].appendChild(div);
	
	initImg();
	window.onresize = function() {initImg()}

	function initImg() {
		_w = getViewSize()["w"];
		div.style.width = _w + "px";
		div.style.maxHeight = _h + "px";
	
		var imgtemp = new Image();//创建一个image对象
		imgtemp.src = img.src;
		imgtemp.onload = function() {//图片加载完成后执行
			var sHeight = _w*this.height/this.width;
			if (sHeight <= _h) {
				img.style.width = "100%";
				img.style.height = "auto";
				img.style.display = "block";
			} else {
				img.style.width = "auto";
				img.style.height = _h + 'px';
				img.style.display = "block";
			}
			
			
			var offset = img.offsetLeft + img.offsetWidth - 20;
			close.style.left = offset + 'px';
		}
	}

	function getViewSize() {//获取浏览器视口的宽高
		return {
			"w": document.documentElement.clientWidth || window['innerWidth'],
			"h": document.documentElement.clientHeight || window['innerHeight']
		}
	}
}

if (window.attachEvent) {
	window.attachEvent("onload",function() {QMSW__addEvent();});
	
	alert($('#QMSW__maskBig_div img').width())
} else {
	window.addEventListener("load",function() {QMSW__addEvent();},true);
}